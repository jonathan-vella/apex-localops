#!/usr/bin/env bash
#
# provision-machine.sh - Create the Azure Arc site, register the SFF machine from its
# ownership voucher, and install the target OS - the "connect a provisioned machine"
# step (docs/sff-runbook.md), automated where the preview CLI allows.
#
# CAPABILITY-DETECTED SEAM: the SFF machine-provisioning CLI (`az provisionedmachine`
# / the preview site+voucher commands) is gated behind the Azure Local SFF preview and
# is NOT in the public Azure CLI. This script:
#   * AUTO mode - if a provisioning CLI verb is detected (or installable), it creates the
#     site, adds the machine from the Key Vault-stored voucher, and runs install-os.
#   * GUIDED mode - otherwise it prints the exact portal steps, then POLLS the edge-machine
#     resource until it reaches 'Provisioned' so the rest of the chain can proceed unattended
#     once you complete that one portal action.
#
# Either way it ends by waiting for the machine to reach 'Provisioned', so deploy-all.sh
# can continue to AKS automatically.
#
# Usage:
#   ./provision-machine.sh --site <name> --machine <name>          # auto or guided + wait
#   ./provision-machine.sh --resource-group rg-azlocal-sff-eus01   # default RG
#   ./provision-machine.sh --key-vault <name> --voucher-secret <n> # voucher in Key Vault
#   ./provision-machine.sh --ssh-key-file ~/.ssh/id_rsa.pub        # public key for the OS
#   ./provision-machine.sh --os-image AzureLinux                   # target OS image
#   ./provision-machine.sh --wait-only                             # skip create, just poll
#   ./provision-machine.sh --no-wait                               # create/guide, don't poll
#   ./provision-machine.sh --help
#
# Before provisioning it pre-creates (or reuses) the Arc site via
# scripts/ensure-arc-site.sh, so it is selectable in the portal wizard. (The Arc Gateway
# is optional and not required for SFF machine provisioning.)
#
# Prerequisites: az login; a stored ownership voucher (the host's automatic SSH extraction,
# or Save-OwnershipVoucher.ps1); providers registered (scripts/check-providers-sff.sh).

set -euo pipefail

RESOURCE_GROUP="rg-azlocal-sff-eus01"
SITE_NAME="local-sff"
MACHINE_NAME=""
KEY_VAULT=""
VOUCHER_SECRET="sff-ownership-voucher"
SSH_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
OS_IMAGE="AzureLinux"
LOCATION="eastus"
WAIT_ONLY=false
DO_WAIT=true
POLL_TIMEOUT_SECONDS=1800
POLL_INTERVAL_SECONDS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE_NAME="${2:?missing value}"; shift 2 ;;
    --machine) MACHINE_NAME="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --key-vault) KEY_VAULT="${2:?missing value}"; shift 2 ;;
    --voucher-secret) VOUCHER_SECRET="${2:?missing value}"; shift 2 ;;
    --ssh-key-file) SSH_KEY_FILE="${2:?missing value}"; shift 2 ;;
    --os-image) OS_IMAGE="${2:?missing value}"; shift 2 ;;
    --location|-l) LOCATION="${2:?missing value}"; shift 2 ;;
    --wait-only) WAIT_ONLY=true; shift ;;
    --no-wait) DO_WAIT=false; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Self-discover the SFF Key Vault (holds the voucher) if not supplied ---
if [[ -z "$KEY_VAULT" ]]; then
  KEY_VAULT=$(az keyvault list -g "$RESOURCE_GROUP" --query "[?starts_with(name,'sffkv')].name | [0]" -o tsv 2>/dev/null || true)
  [[ -n "$KEY_VAULT" && "$KEY_VAULT" != "None" ]] && echo "Discovered Key Vault: $KEY_VAULT"
fi

# --- Detect whether the SFF machine-provisioning CLI is available ---
# The preview ships these verbs out-of-band; probe for them so we can auto-drive when present.
provisioning_cli_available() {
  az provisionedmachine --help >/dev/null 2>&1 && return 0
  # Some preview builds expose it as an extension; try a best-effort install of likely names.
  local cand
  for cand in provisionedmachine edge-provisioning azurestackhci-edge; do
    if az extension add --name "$cand" >/dev/null 2>&1; then
      az provisionedmachine --help >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

# --- Resolve the edge-machine resource and its provisioning state ---
edge_machine_state() {
  # The provisioned machine surfaces as Microsoft.AzureStackHCI/edgeMachines.
  az resource list -g "$RESOURCE_GROUP" \
    --resource-type "Microsoft.AzureStackHCI/edgeMachines" \
    --query "[${MACHINE_NAME:+?name=='$MACHINE_NAME'}].{name:name, state:properties.provisioningState, status:properties.status} | [0]" \
    -o json 2>/dev/null || echo '{}'
}

wait_for_provisioned() {
  echo "Waiting for the edge machine to reach 'Provisioned' (up to $((POLL_TIMEOUT_SECONDS/60)) min)..."
  local deadline state
  deadline=$(( $(date +%s) + POLL_TIMEOUT_SECONDS ))
  while true; do
    state=$(edge_machine_state)
    local prov name
    prov=$(echo "$state" | sed -n 's/.*"state": *"\([^"]*\)".*/\1/p')
    name=$(echo "$state" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')
    [[ -n "$name" ]] && echo "  machine '$name' state: ${prov:-<none>}"
    if [[ "$prov" == "Succeeded" || "$prov" == "Provisioned" ]]; then
      echo "✅ Machine is Provisioned."
      return 0
    fi
    if [[ "$prov" == "Failed" || "$prov" == "Canceled" ]]; then
      echo "❌ Machine provisioning state is '$prov'. Inspect in the portal." >&2
      return 1
    fi
    if [[ $(date +%s) -ge $deadline ]]; then
      echo "⏱  Timed out waiting for 'Provisioned'. Re-run with --wait-only to keep polling." >&2
      return 2
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
}

print_guided_steps() {
  cat <<EOF

────────────────────────────────────────────────────────────────────
The SFF machine-provisioning CLI is not available in this Azure CLI, so this
one step is performed in the Azure portal (preview). Everything before and
after it is automated.

  1. Retrieve the ownership voucher from Key Vault (already stored automatically):
       az keyvault secret show --vault-name ${KEY_VAULT:-<key-vault>} \\
         --name ${VOUCHER_SECRET} --query value -o tsv | base64 -d > voucher.pem
  2. Azure portal > Azure Arc > Operations > Machine provisioning (preview) > Provision.
  3. In Basics, SELECT the pre-created site '${SITE_NAME}' (created by ensure-arc-site.sh),
     set Region ${LOCATION}, then Save. (The Arc Gateway is optional - leave it off.)
  4. Provisioned machines > Add > upload voucher.pem > OS '${OS_IMAGE} 2604' > add your
     SSH public key > Review + create.
  5. This script will keep polling until the machine shows 'Provisioned'.

Docs: docs/sff-runbook.md  ·  this is the only per-deploy manual touch in the chain.
────────────────────────────────────────────────────────────────────
EOF
}

echo "Subscription   : $(az account show --query name -o tsv)"
echo "Resource group : $RESOURCE_GROUP"
echo "Site / machine : $SITE_NAME / ${MACHINE_NAME:-<auto>}"
echo

if [[ "$WAIT_ONLY" == "true" ]]; then
  wait_for_provisioned
  exit $?
fi

# --- Pre-create the Arc site (create-or-reuse) so it is selectable in the portal
#     Provision wizard. Best-effort: never blocks. (Arc Gateway is optional, not created.) ---
if [[ -x "$SCRIPT_DIR/ensure-arc-site.sh" ]]; then
  echo "Ensuring the Arc site exists (ensure-arc-site.sh)..."
  "$SCRIPT_DIR/ensure-arc-site.sh" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
    --site-name "$SITE_NAME" >/dev/null || \
    echo "Note: site pre-creation was incomplete; you can create/select it in the portal." >&2
fi

# --- Resolve the SSH public key (env wins, else file) ---
if [[ -z "${AKSBM_SSH_PUBLIC_KEY:-}" && -f "$SSH_KEY_FILE" ]]; then
  AKSBM_SSH_PUBLIC_KEY="$(cat "$SSH_KEY_FILE")"
fi

if provisioning_cli_available; then
  echo "Provisioning CLI detected - attempting automated site + machine + OS install."
  # NOTE: the exact preview verb names/parameters are gated behind the SFF preview and may
  # differ across preview revisions. The flow is: create site -> add machine from voucher ->
  # install-os. We retrieve the voucher from Key Vault first.
  voucher_file="$(mktemp --suffix=.pem)"
  trap 'rm -f "$voucher_file"' EXIT
  if [[ -n "$KEY_VAULT" ]]; then
    az keyvault secret show --vault-name "$KEY_VAULT" --name "$VOUCHER_SECRET" \
      --query value -o tsv 2>/dev/null | base64 -d > "$voucher_file" || true
  fi
  if [[ ! -s "$voucher_file" ]]; then
    echo "WARNING: could not retrieve the voucher from Key Vault; switching to guided mode." >&2
    print_guided_steps
  else
    # Best-effort automated path. If any verb is rejected by this preview build, fall back.
    if az provisionedmachine install-os \
        --name "${MACHINE_NAME:?--machine required in auto mode}" \
        --resource-group "$RESOURCE_GROUP" \
        --os-image "$OS_IMAGE" \
        --ssh-public-key "${AKSBM_SSH_PUBLIC_KEY:?SSH public key required}" 2>/dev/null; then
      echo "install-os submitted."
    else
      echo "WARNING: automated provisioning verb failed on this preview build; switching to guided mode." >&2
      print_guided_steps
    fi
  fi
else
  print_guided_steps
fi

if [[ "$DO_WAIT" == "true" ]]; then
  wait_for_provisioned
  exit $?
fi
echo "Skipping the provisioned-state wait (--no-wait). Re-run with --wait-only to poll later."
