#!/usr/bin/env bash
#
# deploy-sff.sh - Deploy the Azure Local Small Form Factor (SFF) test environment.
#
# The Windows admin password is NEVER stored on disk. This script prompts for it
# securely (no echo) and passes it through the LOCALSFF_ADMIN_PASSWORD environment
# variable, which main.bicepparam reads via readEnvironmentVariable(). The variable
# lives only for this process.
#
# Usage:
#   ./deploy-sff.sh                        # preflight, prompt, what-if, confirm, deploy, watch
#   ./deploy-sff.sh --what-if-only         # prompt + what-if preview only (no deploy)
#   ./deploy-sff.sh --yes                  # skip the post-what-if confirmation
#   ./deploy-sff.sh --skip-preflight       # skip the pre-deployment validation checks
#   ./deploy-sff.sh --skip-providers       # skip the resource-provider + ZTP feature registration
#   ./deploy-sff.sh --no-monitor           # do not launch scripts/monitor-sff.sh after deploying
#   ./deploy-sff.sh --resource-group <n>   # default: rg-sff-host-swc01
#   ./deploy-sff.sh --location <region>    # default: swedencentral
#   ./deploy-sff.sh --help
#
# The ARM deployment provisions the host VM in ~10-15 min. The host then installs
# Hyper-V and waits for you to stage the ROE ISO + Configurator App into the staging
# storage account (all downloads must be initiated from an Azure resource - the
# Bastion jumpbox or Cloud Shell). After staging, it builds the nested SFF test VM
# and drives it to "ROE setup completed successfully". scripts/monitor-sff.sh makes
# that in-VM phase observable without Bastion/RDP.
#
# Prerequisites: az login; providers + AzureLocalZTP feature registered
# (scripts/check-providers-sff.sh).

set -euo pipefail

RESOURCE_GROUP="rg-sff-host-swc01"
LOCATION="swedencentral"
WHATIF_ONLY=false
SKIP_PROVIDERS=false
ASSUME_YES=false
SKIP_PREFLIGHT=false
RUN_MONITOR=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$REPO_ROOT/infra/bicep/azlocal-sff/main.bicep"
PARAMS="$REPO_ROOT/infra/bicep/azlocal-sff/main.bicepparam"
MONITOR="$SCRIPT_DIR/monitor-sff.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --what-if-only) WHATIF_ONLY=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
    --skip-providers) SKIP_PROVIDERS=true; shift ;;
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

# Nested-virtualization-capable host SKUs (must match the allowed list in main.bicep).
NESTED_VIRT_SKUS=(
  Standard_D8s_v5 Standard_D16s_v5 Standard_E8s_v5 Standard_E16s_v5
  Standard_D8s_v6 Standard_D16s_v6 Standard_E8s_v6 Standard_E16s_v6
)

# --- Validate a candidate password against SFF rules ---
validate_password() {
  local pw="$1"
  if (( ${#pw} < 12 || ${#pw} > 123 )); then
    echo "Password must be 12-123 characters (recommend >= 14)." >&2
    return 1
  fi
  if [[ "$pw" == *'$'* ]]; then
    echo "Password must not contain '\$' (it can break the in-VM logon/bootstrap)." >&2
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
    export LOCALSFF_ADMIN_PASSWORD="$pw"
    break
  done
}

if [[ -n "${LOCALSFF_ADMIN_PASSWORD:-}" ]]; then
  echo "Using password from the LOCALSFF_ADMIN_PASSWORD environment variable." >&2
  validate_password "$LOCALSFF_ADMIN_PASSWORD" || exit 1
else
  prompt_password
fi

# --- Read a param value out of main.bicepparam ---
param_value() {
  local key="$1"
  grep -E "^param ${key}" "$PARAMS" 2>/dev/null | sed -E "s/.*=[[:space:]]*'?([^']*)'?.*/\1/" | head -1
}

# --- Preflight validation: catch the common, expensive-to-discover failures early ---
preflight() {
  local failures=0 warnings=0
  echo "Running preflight checks..."

  # 1) Template compiles.
  if az bicep build --file "$TEMPLATE" --stdout >/dev/null 2>&1; then
    echo "  [ok]   main.bicep compiles"
  else
    echo "  [FAIL] main.bicep does not compile: az bicep build --file \"$TEMPLATE\"" >&2
    failures=$((failures + 1))
  fi

  # 2) Host SKU must be nested-virtualization capable. A non-nested SKU cannot run the
  #    nested ROE test VM at all - this is the single most important SFF preflight.
  local sku found=0 s
  sku=$(param_value hostVmSize)
  [[ -z "$sku" ]] && sku="Standard_D8s_v5"
  for s in "${NESTED_VIRT_SKUS[@]}"; do
    [[ "$s" == "$sku" ]] && found=1 && break
  done
  if [[ "$found" == "1" ]]; then
    echo "  [ok]   host SKU '${sku}' is nested-virtualization capable"
  else
    echo "  [FAIL] host SKU '${sku}' is not in the nested-virt allow-list." >&2
    echo "         Use one of: ${NESTED_VIRT_SKUS[*]}" >&2
    failures=$((failures + 1))
  fi

  # 3) AzureLocalZTP preview feature should be Registered (needed for portal machine
  #    provisioning later; the host build itself works without it).
  local feat
  feat=$(az feature show --namespace Microsoft.DeviceOnboarding --name AzureLocalZTP \
    --query "properties.state" -o tsv 2>/dev/null || echo "NotRegistered")
  if [[ "$feat" == "Registered" ]]; then
    echo "  [ok]   AzureLocalZTP feature registered"
  else
    echo "  [warn] AzureLocalZTP feature state is '${feat}'. Run scripts/check-providers-sff.sh." >&2
    warnings=$((warnings + 1))
  fi

  # 4) Critical resource providers registered.
  local crit=(Microsoft.AzureStackHCI Microsoft.HybridCompute Microsoft.Edge Microsoft.KeyVault Microsoft.Storage)
  local unreg=() rp st
  for rp in "${crit[@]}"; do
    st=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
    [[ "$st" == "Registered" ]] || unreg+=("$rp ($st)")
  done
  if [[ ${#unreg[@]} -eq 0 ]]; then
    echo "  [ok]   critical resource providers registered"
  else
    echo "  [warn] not registered: ${unreg[*]}" >&2
    echo "         Run scripts/check-providers-sff.sh to register them." >&2
    warnings=$((warnings + 1))
  fi

  # 5) Host VM vCPU quota for the chosen family in the target region.
  local letter cpu ver famval qlimit qcur qavail
  if [[ "$sku" =~ ^Standard_([DE])([0-9]+)s_v([0-9]+)$ ]]; then
    letter="${BASH_REMATCH[1]}"
    cpu="${BASH_REMATCH[2]}"
    ver="${BASH_REMATCH[3]}"
    famval="standard${letter}Sv${ver}Family"
    qlimit=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='${famval}'].limit | [0]" -o tsv 2>/dev/null || true)
    qcur=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='${famval}'].currentValue | [0]" -o tsv 2>/dev/null || true)
    if [[ "$qlimit" =~ ^[0-9]+$ && "$qcur" =~ ^[0-9]+$ ]]; then
      qavail=$((qlimit - qcur))
      if (( qavail < cpu )); then
        echo "  [FAIL] insufficient ${famval} quota in ${LOCATION}: need ${cpu} vCPU, ${qavail} free (limit ${qlimit}, used ${qcur})." >&2
        failures=$((failures + 1))
      else
        echo "  [ok]   vCPU quota: ${qavail} free in ${famval}/${LOCATION} (need ${cpu})"
      fi
    else
      echo "  [warn] could not read ${famval} quota in ${LOCATION}; confirm ${cpu} vCPU is available." >&2
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

echo
echo "Subscription   : $(az account show --query name -o tsv)"
echo "Resource group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Template       : $TEMPLATE"
echo

# --- Ensure subscription prerequisites: register the SFF resource providers and the
#     AzureLocalZTP feature (per the subscription-setup doc), registering anything that
#     is missing. Delegated to the canonical check-providers-sff.sh (single source of
#     truth for the provider list); idempotent and fast when already registered. ---
if [[ "$SKIP_PROVIDERS" != "true" ]]; then
  echo "Ensuring required resource providers + AzureLocalZTP feature (registering any missing)..."
  "$SCRIPT_DIR/check-providers-sff.sh" || {
    echo "ERROR: resource-provider/feature registration did not complete. Re-run, or pass --skip-providers to bypass." >&2
    exit 1
  }
  echo
fi

# --- Ensure the resource group exists ---
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group $RESOURCE_GROUP in $LOCATION ..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

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
DEPLOY_NAME="localsff-$(date +%Y%m%d-%H%M%S)"

# Resolve the signed-in user's object id so the deployment grants them Storage Blob Data
# Contributor on the staging account (Owner/Contributor alone can't list/upload blobs in the
# portal). Pre-set LOCALSFF_OPERATOR_PRINCIPAL_ID to override (e.g. a group object id), or set
# it empty to skip. Service-principal logins have no signed-in user, so this stays empty there.
if [[ -z "${LOCALSFF_OPERATOR_PRINCIPAL_ID:-}" ]]; then
  LOCALSFF_OPERATOR_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
fi
export LOCALSFF_OPERATOR_PRINCIPAL_ID
if [[ -n "${LOCALSFF_OPERATOR_PRINCIPAL_ID:-}" ]]; then
  echo "Granting operator ${LOCALSFF_OPERATOR_PRINCIPAL_ID} Storage Blob Data Contributor on the staging account."
fi

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

STAGING_SA=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.outputs.stagingStorageAccountName.value" -o tsv 2>/dev/null || echo "<staging-sa>")
STAGING_CONTAINER=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.outputs.stagingArtifactsContainer.value" -o tsv 2>/dev/null || echo "sff-artifacts")

cat <<EOF

────────────────────────────────────────────────────────────────────
ARM resources are deployed. The host VM is now installing Hyper-V and
configuring the internal NAT network, then it WAITS for the two
Microsoft-owned artifacts to appear in the staging storage account:

    storage account : ${STAGING_SA}
    container       : ${STAGING_CONTAINER}
    blobs           : roe.iso  configurator.msi

ALL downloads must be initiated from an Azure resource. The '${RESOURCE_GROUP}/LocalSFF-Mgmt'
jumpbox is PRE-PROVISIONED for this: Azure CLI + Az PowerShell + the
Publish-SffArtifacts.ps1 helper are installed in C:\\LocalSFF, and a
'SFF-Staging-Instructions.txt' with the exact commands is on its desktop.

  1. RDP to the jumpbox over Bastion (it has the tooling pre-installed).
  2. Azure portal > Azure Arc > Machine provisioning (preview) >
     Get started > View downloads > Download all.
  3. Upload both files to the staging container - easiest is the helper
     (uses the jumpbox managed identity; no extra login):
       C:\\LocalSFF\\Publish-SffArtifacts.ps1 -StorageAccountName ${STAGING_SA} \`
         -IsoPath <roe>.iso -ConfiguratorPath <configurator>.msi
     or with the CLI (az login --identity first):
       az storage blob upload --account-name ${STAGING_SA} \\
         --container-name ${STAGING_CONTAINER} --name roe.iso \\
         --file <roe>.iso --auth-mode login
       az storage blob upload --account-name ${STAGING_SA} \\
         --container-name ${STAGING_CONTAINER} --name configurator.msi \\
         --file <configurator>.msi --auth-mode login

Track the in-VM build (tags + optional host log tail):

    $MONITOR

Success = the RG 'SffProgress' tag reaches 'RoeSucceeded'. Then follow
docs/sff-runbook.md to download the ownership voucher and provision the
machine from the Azure portal.

Tear everything down (stops all billing):  $SCRIPT_DIR/cleanup-sff.sh
────────────────────────────────────────────────────────────────────
EOF

if [[ "$RUN_MONITOR" == "true" && -x "$MONITOR" ]]; then
  echo "Launching monitor (Ctrl-C to stop watching; the build keeps running)..."
  echo
  "$MONITOR" --resource-group "$RESOURCE_GROUP"
else
  echo "Run the monitor yourself when ready:  $MONITOR --resource-group $RESOURCE_GROUP"
fi
