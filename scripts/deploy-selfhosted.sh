#!/usr/bin/env bash
#
# deploy-selfhosted.sh - Deploy the SELF-HOSTED Azure Local lab (zero Jumpstart).
#
# Stands up: a hardened ISO storage account, a Windows Server 2025 jumpbox, a large
# nested-virtualization cluster host, Bastion, NAT Gateway, and Log Analytics. The
# host then builds a nested domain controller + a 3-node Azure Local cluster from
# two ISOs you stage on the jumpbox - NO prebaked VHDs, NO Jumpstart modules.
#
# The Windows admin password is NEVER stored on disk. This script prompts for it
# securely (no echo) and passes it via LOCALSELF_ADMIN_PASSWORD, which
# main.bicepparam reads with readEnvironmentVariable(). It also resolves the
# deployer object id and the Azure Local RP object id at deploy time.
#
# Usage:
#   ./deploy-selfhosted.sh                       # preflight, prompt, what-if, confirm, deploy, watch
#   ./deploy-selfhosted.sh --what-if-only        # prompt + what-if preview only (no deploy)
#   ./deploy-selfhosted.sh --yes                 # skip the post-what-if confirmation
#   ./deploy-selfhosted.sh --skip-preflight      # skip the pre-deployment validation checks
#   ./deploy-selfhosted.sh --no-monitor          # do not launch scripts/monitor-selfhosted.sh
#   ./deploy-selfhosted.sh --resource-group <n>  # default: rg-apexlocal
#   ./deploy-selfhosted.sh --location <region>   # default: swedencentral
#   ./deploy-selfhosted.sh --help
#
# Prerequisites: az login; providers + Azure Local RP object id resolved
# (scripts/check-providers-selfhosted.sh).

set -euo pipefail

RESOURCE_GROUP="rg-apexlocal"
LOCATION="swedencentral"
WHATIF_ONLY=false
ASSUME_YES=false
SKIP_PREFLIGHT=false
RUN_MONITOR=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$REPO_ROOT/infra/bicep/azlocal-selfhosted/main.bicep"
PARAMS="$REPO_ROOT/infra/bicep/azlocal-selfhosted/main.bicepparam"
MONITOR="$SCRIPT_DIR/monitor-selfhosted.sh"

HCI_RP_APP_ID="1412d89f-b8a8-4111-b4fd-e82905cbd85d"

# High-memory, nested-virtualization-capable host SKUs (must match main.bicep).
HOST_SKUS=(
  Standard_E32s_v5 Standard_E48s_v5 Standard_E64s_v5
  Standard_E32s_v6 Standard_E48s_v6 Standard_E64s_v6
)

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

# --- Validate a candidate password against the Windows complexity rules ---
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
    export LOCALSELF_ADMIN_PASSWORD="$pw"
    break
  done
}

if [[ -n "${LOCALSELF_ADMIN_PASSWORD:-}" ]]; then
  echo "Using password from the LOCALSELF_ADMIN_PASSWORD environment variable." >&2
  validate_password "$LOCALSELF_ADMIN_PASSWORD" || exit 1
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

  # 2) Host SKU must be in the high-memory nested-virt allow-list.
  local sku found=0 s
  sku=$(param_value hostVmSize)
  [[ -z "$sku" ]] && sku="Standard_E64s_v6"
  for s in "${HOST_SKUS[@]}"; do
    [[ "$s" == "$sku" ]] && found=1 && break
  done
  if [[ "$found" == "1" ]]; then
    echo "  [ok]   host SKU '${sku}' is in the supported list"
  else
    echo "  [FAIL] host SKU '${sku}' is not in the allow-list." >&2
    echo "         Use one of: ${HOST_SKUS[*]}" >&2
    failures=$((failures + 1))
  fi

  # 3) Critical resource providers registered.
  local crit=(Microsoft.AzureStackHCI Microsoft.HybridCompute Microsoft.ExtendedLocation Microsoft.EdgeMarketplace Microsoft.KeyVault Microsoft.Storage)
  local unreg=() rp st
  for rp in "${crit[@]}"; do
    st=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
    [[ "$st" == "Registered" ]] || unreg+=("$rp ($st)")
  done
  if [[ ${#unreg[@]} -eq 0 ]]; then
    echo "  [ok]   critical resource providers registered"
  else
    echo "  [warn] not registered: ${unreg[*]}" >&2
    echo "         Run scripts/check-providers-selfhosted.sh to register them." >&2
    warnings=$((warnings + 1))
  fi

  # 4) Azure Local RP object id resolvable (needed by the in-VM cluster deploy).
  if [[ -n "${LOCALSELF_HCI_RP_OBJECT_ID:-}" ]]; then
    echo "  [ok]   Azure Local RP object id provided via LOCALSELF_HCI_RP_OBJECT_ID"
  else
    local oid
    oid=$(az ad sp show --id "$HCI_RP_APP_ID" --query id -o tsv 2>/dev/null || true)
    if [[ -n "${oid:-}" ]]; then
      echo "  [ok]   Azure Local RP object id resolvable (${oid})"
    else
      echo "  [warn] could not resolve the Azure Local RP object id. Run scripts/check-providers-selfhosted.sh." >&2
      warnings=$((warnings + 1))
    fi
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

# --- Ensure the resource group exists ---
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group $RESOURCE_GROUP in $LOCATION ..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
  preflight
fi

# --- Resolve identity inputs (never committed) ---
# Deployer object id -> Storage Blob Data Owner (ISO upload). Service-principal logins
# have no signed-in user, so this stays empty there (set LOCALSELF_DEPLOYER_PRINCIPAL_ID).
if [[ -z "${LOCALSELF_DEPLOYER_PRINCIPAL_ID:-}" ]]; then
  LOCALSELF_DEPLOYER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
fi
export LOCALSELF_DEPLOYER_PRINCIPAL_ID
if [[ -n "${LOCALSELF_DEPLOYER_PRINCIPAL_ID:-}" ]]; then
  echo "Granting deployer ${LOCALSELF_DEPLOYER_PRINCIPAL_ID} Storage Blob Data Owner on the ISO account."
fi

# Azure Local RP object id -> required by the in-VM cluster deploy.
if [[ -z "${LOCALSELF_HCI_RP_OBJECT_ID:-}" ]]; then
  LOCALSELF_HCI_RP_OBJECT_ID=$(az ad sp show --id "$HCI_RP_APP_ID" --query id -o tsv 2>/dev/null || true)
fi
export LOCALSELF_HCI_RP_OBJECT_ID
if [[ -n "${LOCALSELF_HCI_RP_OBJECT_ID:-}" ]]; then
  echo "Azure Local RP object id: ${LOCALSELF_HCI_RP_OBJECT_ID}"
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
DEPLOY_NAME="apexlocal-$(date +%Y%m%d-%H%M%S)"

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
ISO_CONTAINER=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.outputs.isoContainerName.value" -o tsv 2>/dev/null || echo "iso-images")
MGMT_VM=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.outputs.managementVmName.value" -o tsv 2>/dev/null || echo "ApexLocal-Mgmt")

cat <<EOF

────────────────────────────────────────────────────────────────────
ARM resources are deployed. The cluster host is installing Hyper-V,
pooling its data disks into V:, and configuring the internal network,
then it WAITS for BOTH ISOs to appear in the storage account:

    storage account : ${STAGING_SA}
    container       : ${ISO_CONTAINER}
    blobs           : AzureLocalOS.iso  WindowsServer.iso

This is the ONE manual step. All downloads stay inside Azure - the
'${RESOURCE_GROUP}/${MGMT_VM}' jumpbox is PRE-PROVISIONED for it
(Azure CLI + Az PowerShell + AzCopy + Upload-Isos.ps1 in C:\\ApexLocal,
and STAGE-ISOS-README.txt on its desktop):

  1. RDP to the jumpbox over Bastion.
  2. Download the Azure Local OS ISO (Azure portal > Azure Local >
     Get started > Download software) and the Windows Server 2025 ISO
     (microsoft.com/evalcenter).
  3. Upload both (uses the jumpbox managed identity; no extra login):
       Connect-AzAccount -Identity
       C:\\ApexLocal\\Upload-Isos.ps1 -StorageAccountName ${STAGING_SA} \`
         -AzureLocalIsoPath <azurelocal>.iso \`
         -WindowsServerIsoPath <windowsserver>.iso

Track the in-VM build (tags + optional host log tail):

    $MONITOR

Success = the RG 'ApexProgress' tag reaches 'Completed' AND
'az stack-hci cluster list -g ${RESOURCE_GROUP}' shows the cluster
ProvisioningState=Succeeded, ConnectivityStatus=Connected.

Tear everything down (stops all billing):  $SCRIPT_DIR/cleanup-selfhosted.sh
────────────────────────────────────────────────────────────────────
EOF

if [[ "$RUN_MONITOR" == "true" && -x "$MONITOR" ]]; then
  echo "Launching $MONITOR ..."
  exec "$MONITOR" --resource-group "$RESOURCE_GROUP"
fi
