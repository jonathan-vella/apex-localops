#!/usr/bin/env bash
#
# deploy.sh - Deploy the customized LocalBox template to Sweden Central.
#
# The Windows admin password is NEVER stored on disk. This script prompts for it
# securely (no echo) and passes it to the deployment through the
# LOCALBOX_ADMIN_PASSWORD environment variable, which main.bicepparam reads via
# readEnvironmentVariable(). The variable lives only for this process.
#
# Usage:
#   ./deploy.sh                        # preflight, prompt, what-if, confirm, deploy, watch
#   ./deploy.sh --what-if-only         # prompt + what-if preview only (no deploy)
#   ./deploy.sh --yes                  # skip the post-what-if confirmation
#   ./deploy.sh --skip-preflight       # skip the pre-deployment validation checks
#   ./deploy.sh --no-monitor           # do not launch scripts/monitor.sh after deploying
#   ./deploy.sh --resource-group <n>   # default: rg-localbox
#   ./deploy.sh --location <region>    # default: swedencentral
#   ./deploy.sh --help
#
# The ARM deployment finishes in ~18 min, but the nested Azure Local cluster then builds
# INSIDE the client VM for 2-4 hours with no Azure-visible deployment state. After a
# successful deploy this script hands off to scripts/monitor.sh so that in-VM phase is
# observable (it was previously invisible). Use --no-monitor to skip that.
#
# Identity GUIDs are NOT stored in the repo. This script resolves them at runtime and
# exports them for main.bicepparam (which reads them via readEnvironmentVariable):
#   LOCALBOX_TENANT_ID        <- az account show --query tenantId
#   LOCALBOX_SPN_PROVIDER_ID  <- Microsoft.AzureStackHCI Resource Provider object id
# Pre-set either var to override the auto-resolved value.
#
# Prerequisites: az login; providers registered (scripts/check-providers.sh).

set -euo pipefail

RESOURCE_GROUP="rg-localbox"
LOCATION="swedencentral"
WHATIF_ONLY=false
ASSUME_YES=false
SKIP_PREFLIGHT=false
RUN_MONITOR=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$REPO_ROOT/bicep/main.bicep"
PARAMS="$REPO_ROOT/bicep/main.bicepparam"
MONITOR="$SCRIPT_DIR/monitor.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --what-if-only) WHATIF_ONLY=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
    --no-monitor) RUN_MONITOR=false; shift ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --location|-l) LOCATION="${2:?missing value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "ERROR: template not found: $TEMPLATE" >&2; exit 1; }
[[ -f "$PARAMS" ]] || { echo "ERROR: params not found: $PARAMS" >&2; exit 1; }

# --- Validate a candidate password against LocalBox rules ---
validate_password() {
  local pw="$1"
  if (( ${#pw} < 12 || ${#pw} > 123 )); then
    echo "Password must be 12-123 characters (LocalBox recommends >= 14)." >&2
    return 1
  fi
  if [[ "$pw" == *'$'* ]]; then
    echo "Password must not contain '\$' (it breaks the LocalBox LogonScript)." >&2
    return 1
  fi
  return 0
}

# --- Prompt for the Windows admin password (never written to disk) ---
prompt_password() {
  local pw pw2
  while true; do
    printf 'Enter the Windows admin password (14-123 chars; avoid the $ character): ' >&2
    IFS= read -rs pw || { echo >&2; echo "Aborted." >&2; exit 1; }
    printf '\n' >&2
    printf 'Confirm the password: ' >&2
    IFS= read -rs pw2 || { echo >&2; echo "Aborted." >&2; exit 1; }
    printf '\n' >&2

    if [[ "$pw" != "$pw2" ]]; then
      echo "Passwords do not match. Try again." >&2
      continue
    fi
    validate_password "$pw" || continue
    export LOCALBOX_ADMIN_PASSWORD="$pw"
    break
  done
}

# Use a pre-set LOCALBOX_ADMIN_PASSWORD (e.g. exported in the shell or from CI) if
# present; otherwise prompt interactively. Either way it is never written to disk.
if [[ -n "${LOCALBOX_ADMIN_PASSWORD:-}" ]]; then
  echo "Using password from the LOCALBOX_ADMIN_PASSWORD environment variable." >&2
  validate_password "$LOCALBOX_ADMIN_PASSWORD" || exit 1
else
  prompt_password
fi

# --- Preflight validation: catch the common, expensive-to-discover failures early ---
# Each check maps to a real failure mode that otherwise only surfaces after the ~18 min
# ARM deploy or deep inside the 2-4 h in-VM cluster build.
preflight() {
  local failures=0 warnings=0
  echo "Running preflight checks..."

  # 1) Template compiles (fast-fail on Bicep errors before the minutes-long what-if).
  if az bicep build --file "$TEMPLATE" --stdout >/dev/null 2>&1; then
    echo "  [ok]   main.bicep compiles"
  else
    echo "  [FAIL] main.bicep does not compile: az bicep build --file \"$TEMPLATE\"" >&2
    failures=$((failures + 1))
  fi

  # 2) spnProviderId must resolve to a real GUID. The in-VM Arc registration depends on
  #    it; a bad value wastes the entire build. (Resolved + exported above.)
  if [[ "${LOCALBOX_SPN_PROVIDER_ID:-}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "  [ok]   spnProviderId resolved"
  else
    echo "  [FAIL] spnProviderId did not resolve. Run scripts/check-providers.sh, or export LOCALBOX_SPN_PROVIDER_ID." >&2
    failures=$((failures + 1))
  fi

  # 3) Critical resource providers registered (the cluster build needs these).
  local crit=(Microsoft.AzureStackHCI Microsoft.HybridCompute Microsoft.ExtendedLocation Microsoft.ResourceConnector Microsoft.KubernetesConfiguration)
  local unreg=() rp st
  for rp in "${crit[@]}"; do
    st=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
    [[ "$st" == "Registered" ]] || unreg+=("$rp ($st)")
  done
  if [[ ${#unreg[@]} -eq 0 ]]; then
    echo "  [ok]   critical resource providers registered"
  else
    echo "  [warn] not registered: ${unreg[*]}" >&2
    echo "         Run scripts/check-providers.sh to register them." >&2
    warnings=$((warnings + 1))
  fi

  # 4) Witness/staging SA region invariant. The staging storage account doubles as the
  #    Azure Local cluster witness, which azlocal.json creates in azureLocalInstanceLocation.
  #    If one already exists in another region, the in-VM cloud deployment aborts with
  #    InvalidResourceLocation (the exact failure this project hit).
  local instloc existing
  instloc=$(grep -E "^param azureLocalInstanceLocation" "$PARAMS" 2>/dev/null | sed -E "s/.*=[[:space:]]*'([^']*)'.*/\1/")
  if az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
    existing=$(az storage account list -g "$RESOURCE_GROUP" --query "[?starts_with(name,'localbox')].location | [0]" -o tsv 2>/dev/null || true)
    if [[ -n "$existing" && "$existing" != "None" && -n "$instloc" && "$existing" != "$instloc" ]]; then
      echo "  [FAIL] staging/witness SA is in '$existing' but azureLocalInstanceLocation='$instloc'." >&2
      echo "         The Azure Local cluster witness must live in '$instloc'. Delete that SA, then redeploy." >&2
      failures=$((failures + 1))
    else
      echo "  [ok]   staging/witness SA region invariant"
    fi
  fi

  # 5) Host VM vCPU quota. The 3-node default needs a 64-vCPU Esv6 SKU; a quota shortfall
  #    otherwise surfaces only after the ~18 min ARM deploy. Fails when clearly insufficient,
  #    warns when it can't be determined.
  local sku reqcpu ver famval qlimit qcur qavail
  sku=$(grep -E "^param vmSize" "$PARAMS" 2>/dev/null | sed -E "s/.*=[[:space:]]*'([^']*)'.*/\1/")
  reqcpu=$(printf '%s' "$sku" | sed -E 's/^Standard_E([0-9]+)s_v[0-9]+$/\1/')
  ver=$(printf '%s' "$sku" | sed -E 's/.*_(v[0-9]+)$/\1/')
  famval="standardES${ver}Family"
  if [[ "$reqcpu" =~ ^[0-9]+$ ]]; then
    qlimit=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='${famval}'].limit | [0]" -o tsv 2>/dev/null || true)
    qcur=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='${famval}'].currentValue | [0]" -o tsv 2>/dev/null || true)
    if [[ "$qlimit" =~ ^[0-9]+$ && "$qcur" =~ ^[0-9]+$ ]]; then
      qavail=$((qlimit - qcur))
      if (( qavail < reqcpu )); then
        echo "  [FAIL] insufficient ${famval} quota in ${LOCATION}: need ${reqcpu} vCPU, ${qavail} free (limit ${qlimit}, used ${qcur})." >&2
        echo "         Request a quota increase, or deploy a smaller SKU/region." >&2
        failures=$((failures + 1))
      else
        echo "  [ok]   vCPU quota: ${qavail} free in ${famval}/${LOCATION} (need ${reqcpu})"
      fi
    else
      echo "  [warn] could not read ${famval} quota in ${LOCATION}; confirm ${reqcpu:-64} vCPU is available before deploying." >&2
      warnings=$((warnings + 1))
    fi
  fi

  echo
  if (( failures > 0 )); then
    echo "Preflight found $failures blocking issue(s). Fix them, or re-run with --skip-preflight." >&2
    exit 1
  fi
  (( warnings > 0 )) && echo "Preflight passed with $warnings warning(s)." || echo "Preflight passed."
  echo
}

# --- Resolve identity GUIDs at runtime (kept out of the public repo) and export them
#     so main.bicepparam can read them via readEnvironmentVariable(). Pre-set values win.
if [[ -z "${LOCALBOX_TENANT_ID:-}" ]]; then
  LOCALBOX_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || true)
fi
if [[ -z "${LOCALBOX_SPN_PROVIDER_ID:-}" ]]; then
  LOCALBOX_SPN_PROVIDER_ID=$(az ad sp list --display-name "Microsoft.AzureStackHCI Resource Provider" --query "[0].id" -o tsv 2>/dev/null || true)
fi
export LOCALBOX_TENANT_ID LOCALBOX_SPN_PROVIDER_ID

echo
echo "Subscription   : $(az account show --query name -o tsv)"
echo "Resource group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Template       : $TEMPLATE"
echo

# --- Ensure the resource group exists ---
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group $RESOURCE_GROUP in $LOCATION ..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

# --- Preflight (after RG exists so the witness-SA region check can run) ---
if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
  preflight
fi

# --- What-if preview ---
echo "Running what-if preview..."
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS"

if [[ "$WHATIF_ONLY" == "true" ]]; then
  echo "--what-if-only: stopping before deployment."
  exit 0
fi

# --- Confirm before deploying billable infrastructure ---
if [[ "$ASSUME_YES" != "true" ]]; then
  printf 'Proceed with deployment of billable resources? [y/N]: ' >&2
  IFS= read -r reply || reply=""
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "Deploying..."
DEPLOY_NAME="localbox-$(date +%Y%m%d-%H%M%S)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS" \
  --name "$DEPLOY_NAME"

state=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
echo
echo "ARM deployment '$DEPLOY_NAME' finished: $state"
if [[ "$state" != "Succeeded" ]]; then
  echo "Deployment did not succeed. Inspect: az deployment group show -g $RESOURCE_GROUP -n $DEPLOY_NAME" >&2
  exit 1
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
ARM resources are deployed, but the nested Azure Local cluster now
builds INSIDE the client VM for ~2-4 hours. That phase has no
Azure-visible deployment state; track it without Bastion/RDP using:

    $MONITOR

Success = the Microsoft.AzureStackHCI/clusters resource reaches
provisioningState 'Succeeded' (or the RG 'DeploymentProgress' tag
becomes 'Completed').

If the in-VM build fails, re-run just the cluster cloud deployment
(without rebuilding the nodes):  $SCRIPT_DIR/recover-cluster.sh
Tear everything down (stops all billing):  $SCRIPT_DIR/cleanup.sh
────────────────────────────────────────────────────────────────────
EOF

if [[ "$RUN_MONITOR" == "true" && -x "$MONITOR" ]]; then
  echo "Launching monitor (Ctrl-C to stop watching; the build keeps running)..."
  echo
  "$MONITOR" --resource-group "$RESOURCE_GROUP"
else
  echo "Run the monitor yourself when ready:  $MONITOR --resource-group $RESOURCE_GROUP"
fi
