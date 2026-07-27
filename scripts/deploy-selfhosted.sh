#!/usr/bin/env bash
set -euo pipefail

# Deploy the fixed three-node self-hosted Azure Local evaluation profile.
# Technical preflight is mandatory. Azure Hybrid Benefit is on by default and self-attests that
# the deploying organization holds qualifying Windows Server licenses; pass
# --disable-azure-hybrid-benefit for license-included (PAYG) billing.

RESOURCE_GROUP="rg-apexlocal"
LOCATION="swedencentral"
WHAT_IF_ONLY=false
RUN_MONITOR=true
ARTIFACT_REF="v1.3.0-rc.1"
CLUSTER_NAME="apexlocal"
ENABLE_AZURE_HYBRID_BENEFIT=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$REPO_ROOT/infra/bicep/azlocal-selfhosted/main.bicep"
PARAMS="$REPO_ROOT/infra/bicep/azlocal-selfhosted/main.bicepparam"
MONITOR="$SCRIPT_DIR/monitor-selfhosted.sh"
HCI_RP_APP_ID="1412d89f-b8a8-4111-b4fd-e82905cbd85d"
HOST_SKU="Standard_E64s_v6"
HOST_VCPU=64
HOST_QUOTA_FAMILY="StandardEsv6Family"
WINDOWS_IMAGE_URN="MicrosoftWindowsServer:WindowsServer:2025-datacenter-g2:26100.33158.260711"
REQUIRED_PROVIDERS=(
  Microsoft.HybridCompute Microsoft.GuestConfiguration Microsoft.HybridConnectivity
  Microsoft.AzureStackHCI Microsoft.Kubernetes Microsoft.KubernetesConfiguration
  Microsoft.ExtendedLocation Microsoft.ResourceConnector Microsoft.HybridContainerService
  Microsoft.EdgeMarketplace Microsoft.Attestation Microsoft.Network Microsoft.Storage Microsoft.Insights Microsoft.KeyVault
)
NETWORK_FEATURE="AllowBringYourOwnPublicIpAddress"
RUNTIME_ARTIFACTS=(
  artifacts/selfhosted/PowerShell/Bootstrap.ps1
  artifacts/selfhosted/PowerShell/Setup-Jumpbox.ps1
  artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1
  artifacts/selfhosted/PowerShell/ModuleVersions.psd1
  artifacts/selfhosted/PowerShell/Get-ApexAzureLocalIso.ps1
  artifacts/selfhosted/PowerShell/Get-ApexWindowsServerIso.ps1
  artifacts/selfhosted/PowerShell/New-ApexLocalCluster.ps1
  artifacts/selfhosted/PowerShell/Stage-ApexIsos.ps1
  artifacts/selfhosted/PowerShell/Upload-Isos.ps1
  artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psd1
  artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psm1
  artifacts/selfhosted/azlocal.json
)

usage() {
  printf '%s\n' \
    'Usage: deploy-selfhosted.sh [options]' \
    '  --what-if-only' \
    '  --no-monitor' \
    '  --resource-group, -g <name>' \
    '  --location, -l <swedencentral|germanywestcentral>' \
    '  --artifact-ref <immutable-sha-or-tag>' \
    '  --cluster-name <name>' \
    '  --disable-azure-hybrid-benefit   Bill Windows Server at the license-included (PAYG) rate' \
    '  --help, -h' \
    '' \
    'Set LOCALSELF_ADMIN_PASSWORD before running; it is never written to disk.' \
    'Azure Hybrid Benefit is ON by default; enabling it self-attests that you hold qualifying' \
    'Windows Server licenses. See docs/selfhosted/sizing.md#azure-hybrid-benefit.'
}

validate_password() {
  local password="$1"
  if (( ${#password} < 12 || ${#password} > 123 )); then
    echo "ERROR: LOCALSELF_ADMIN_PASSWORD must be 12-123 characters." >&2
    return 1
  fi
  if [[ "$password" == *'$'* ]]; then
    echo "ERROR: LOCALSELF_ADMIN_PASSWORD must not contain the dollar character." >&2
    return 1
  fi
}

preflight() {
  local failures=0 state provider artifact_path artifact_url
  local account_type account_name principal_id role_names sku_json qlimit qcur qavail
  local unregistered=()

  echo "Running mandatory preflight checks..."
  if [[ "$LOCATION" == "swedencentral" || "$LOCATION" == "germanywestcentral" ]]; then
    echo "  [ok]   infrastructure region '$LOCATION'"
  else
    echo "  [FAIL] unsupported region '$LOCATION'." >&2
    failures=$((failures + 1))
  fi
  if [[ "$CLUSTER_NAME" =~ ^[A-Za-z][A-Za-z0-9-]{2,14}$ ]]; then
    echo "  [ok]   cluster name '$CLUSTER_NAME'"
  else
    echo "  [FAIL] cluster name must start with a letter and contain 3-15 alphanumeric/hyphen characters." >&2
    failures=$((failures + 1))
  fi
  if [[ "$ARTIFACT_REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "  [ok]   artifact ref '$ARTIFACT_REF'"
  else
    echo "  [FAIL] artifact ref contains unsupported characters." >&2
    failures=$((failures + 1))
  fi
  if az bicep build --file "$TEMPLATE" --stdout >/dev/null 2>&1 &&
      az bicep lint --file "$TEMPLATE" >/dev/null 2>&1; then
    echo "  [ok]   main.bicep builds and lints"
  else
    echo "  [FAIL] main.bicep build or lint failed." >&2
    failures=$((failures + 1))
  fi

  for provider in "${REQUIRED_PROVIDERS[@]}"; do
    state=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo Unknown)
    [[ "$state" == "Registered" ]] || unregistered+=("$provider ($state)")
  done
  if (( ${#unregistered[@]} == 0 )); then
    echo "  [ok]   required resource providers registered"
  else
    echo "  [FAIL] providers not registered: ${unregistered[*]}" >&2
    failures=$((failures + 1))
  fi

  state=$(az feature show --namespace Microsoft.Network --name "$NETWORK_FEATURE" \
    --query properties.state -o tsv 2>/dev/null || echo NotRegistered)
  if [[ "$state" == "Registered" ]]; then
    echo "  [ok]   Microsoft.Network/$NETWORK_FEATURE registered"
  else
    echo "  [FAIL] Microsoft.Network/$NETWORK_FEATURE is '$state'. Run scripts/check-providers-selfhosted.sh." >&2
    failures=$((failures + 1))
  fi

  if [[ -z "${LOCALSELF_HCI_RP_OBJECT_ID:-}" ]]; then
    LOCALSELF_HCI_RP_OBJECT_ID=$(az ad sp show --id "$HCI_RP_APP_ID" --query id -o tsv 2>/dev/null || true)
    export LOCALSELF_HCI_RP_OBJECT_ID
  fi
  if [[ -n "${LOCALSELF_HCI_RP_OBJECT_ID:-}" ]]; then
    echo "  [ok]   Azure Local RP object id resolved"
  else
    echo "  [FAIL] Azure Local RP object id could not be resolved." >&2
    failures=$((failures + 1))
  fi

  account_type=$(az account show --query user.type -o tsv)
  account_name=$(az account show --query user.name -o tsv)
  if [[ "$account_type" == "user" ]]; then
    principal_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  else
    principal_id=$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || true)
  fi
  role_names=""
  if [[ -n "$principal_id" ]]; then
    role_names=$(az role assignment list --assignee "$principal_id" --include-groups \
      --include-inherited --all --query '[].roleDefinitionName' -o tsv 2>/dev/null || true)
  fi
  if grep -qx Owner <<<"$role_names" || {
      grep -qx Contributor <<<"$role_names" &&
      grep -Eqx 'User Access Administrator|Role Based Access Control Administrator' <<<"$role_names";
    }; then
    echo "  [ok]   deployment principal can create resources and role assignments"
  else
    echo "  [FAIL] principal needs Owner, or Contributor plus UAA/RBAC Administrator." >&2
    failures=$((failures + 1))
  fi

  sku_json=$(az vm list-skus --location "$LOCATION" --size "$HOST_SKU" --all \
    --query "[?name=='${HOST_SKU}']" -o json 2>/dev/null || echo '[]')
  if jq -e --arg location "$LOCATION" '
      length > 0 and
      ([.[0].restrictions[]? |
        select(.type == "Location" and ((.restrictionInfo.locations // []) | index($location)))] | length == 0)
    ' >/dev/null <<<"$sku_json"; then
    echo "  [ok]   $HOST_SKU unrestricted in $LOCATION"
  else
    echo "  [FAIL] $HOST_SKU unavailable or restricted in $LOCATION." >&2
    failures=$((failures + 1))
  fi

  qlimit=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='${HOST_QUOTA_FAMILY}'].limit | [0]" -o tsv 2>/dev/null || true)
  qcur=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='${HOST_QUOTA_FAMILY}'].currentValue | [0]" -o tsv 2>/dev/null || true)
  if [[ "$qlimit" =~ ^[0-9]+$ && "$qcur" =~ ^[0-9]+$ ]]; then
    qavail=$((qlimit - qcur))
    if (( qavail >= HOST_VCPU )); then
      echo "  [ok]   ${qavail} ${HOST_QUOTA_FAMILY} vCPUs available"
    else
      echo "  [FAIL] need ${HOST_VCPU} free vCPUs; ${qavail} available." >&2
      failures=$((failures + 1))
    fi
  else
    echo "  [FAIL] unable to read ${HOST_QUOTA_FAMILY} quota." >&2
    failures=$((failures + 1))
  fi

  if az vm image show --location "$LOCATION" --urn "$WINDOWS_IMAGE_URN" --output none 2>/dev/null; then
    echo "  [ok]   pinned Windows Server image available"
  else
    echo "  [FAIL] pinned Windows Server image unavailable in $LOCATION." >&2
    failures=$((failures + 1))
  fi

  for artifact_path in "${RUNTIME_ARTIFACTS[@]}"; do
    artifact_url="https://raw.githubusercontent.com/jonathan-vella/apex-localops/${ARTIFACT_REF}/${artifact_path}"
    if ! curl --fail --silent --show-error --location --head "$artifact_url" >/dev/null; then
      echo "  [FAIL] runtime artifact not reachable: $artifact_url" >&2
      failures=$((failures + 1))
    fi
  done
  if (( failures == 0 )); then
    echo "  [ok]   immutable runtime artifact set reachable"
  else
    echo "Preflight found $failures blocking issue(s). No resources were created." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --what-if-only) WHAT_IF_ONLY=true; shift ;;
    --no-monitor) RUN_MONITOR=false; shift ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --location|-l) LOCATION="${2:?missing value}"; shift 2 ;;
    --artifact-ref) ARTIFACT_REF="${2:?missing value}"; shift 2 ;;
    --cluster-name) CLUSTER_NAME="${2:?missing value}"; shift 2 ;;
    --disable-azure-hybrid-benefit) ENABLE_AZURE_HYBRID_BENEFIT=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for command_name in az curl jq; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "ERROR: $command_name not found on PATH." >&2; exit 1; }
done
az account show >/dev/null 2>&1 || { echo "ERROR: not logged in to Azure." >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "ERROR: template not found: $TEMPLATE" >&2; exit 1; }
[[ -f "$PARAMS" ]] || { echo "ERROR: parameters not found: $PARAMS" >&2; exit 1; }

printf '%s\n' \
  "Subscription         : $(az account show --query name -o tsv)" \
  "Resource group       : $RESOURCE_GROUP" \
  "Infrastructure region: $LOCATION" \
  "Cluster name         : $CLUSTER_NAME" \
  "Artifact ref         : $ARTIFACT_REF" \
  "Azure Hybrid Benefit : $ENABLE_AZURE_HYBRID_BENEFIT"
if [[ "$ENABLE_AZURE_HYBRID_BENEFIT" == "true" ]]; then
  # Entitlement is per deploying organization; Azure does not verify it at deployment time.
  printf '%s\n' \
    '  Windows Server bills at the Hybrid Benefit rate. Enabling it self-attests that you hold' \
    '  qualifying Windows Server licenses. Use --disable-azure-hybrid-benefit for PAYG billing.'
fi
preflight

if [[ -z "${LOCALSELF_ADMIN_PASSWORD:-}" ]]; then
  echo "ERROR: set LOCALSELF_ADMIN_PASSWORD after preflight and rerun." >&2
  exit 1
fi
validate_password "$LOCALSELF_ADMIN_PASSWORD"
trap 'unset LOCALSELF_ADMIN_PASSWORD' EXIT

if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
fi
DEPLOYMENT_PARAMETERS=(
  "$PARAMS"
  "location=$LOCATION"
  "artifactRef=$ARTIFACT_REF"
  "clusterName=$CLUSTER_NAME"
  "enableAzureHybridBenefit=$ENABLE_AZURE_HYBRID_BENEFIT"
)

echo "Running what-if preview..."
az deployment group what-if --resource-group "$RESOURCE_GROUP" --template-file "$TEMPLATE" \
  --parameters "${DEPLOYMENT_PARAMETERS[@]}"
if [[ "$WHAT_IF_ONLY" == "true" ]]; then
  echo "What-if complete; no deployment was created."
  exit 0
fi

DEPLOYMENT_NAME="apexlocal-$(date +%Y%m%d-%H%M%S)"
echo "Deploying evaluation as '$DEPLOYMENT_NAME'..."
az deployment group create --resource-group "$RESOURCE_GROUP" --template-file "$TEMPLATE" \
  --parameters "${DEPLOYMENT_PARAMETERS[@]}" --name "$DEPLOYMENT_NAME" --output none
DEPLOYMENT_STATE=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" \
  --query properties.provisioningState -o tsv)
[[ "$DEPLOYMENT_STATE" == "Succeeded" ]] || { echo "ERROR: deployment state is '$DEPLOYMENT_STATE'." >&2; exit 1; }

STAGING_ACCOUNT=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" \
  --query properties.outputs.stagingStorageAccountName.value -o tsv)
ISO_CONTAINER=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" \
  --query properties.outputs.isoContainerName.value -o tsv)
MANAGEMENT_VM=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" \
  --query properties.outputs.managementVmName.value -o tsv)
printf '%s\n' \
  '' \
  'ARM resources are deployed. The host waits for both ISOs and iso-manifest.json.' \
  "Use Bastion to reach ${RESOURCE_GROUP}/${MANAGEMENT_VM}, download both ISOs, then run:" \
  '' \
  '  Connect-AzAccount -Identity' \
  "  C:\\ApexLocal\\Upload-Isos.ps1 -StorageAccountName ${STAGING_ACCOUNT} \`" \
  '    -AzureLocalIsoPath <azurelocal>.iso \`' \
  '    -WindowsServerIsoPath <windowsserver>.iso' \
  '' \
  "The tool uploads to '${ISO_CONTAINER}', verifies both files, and publishes the manifest last." \
  'Raw az storage blob uploads are unsupported because they omit the integrity manifest.' \
  "Monitor: $MONITOR --resource-group $RESOURCE_GROUP" \
  "Cleanup: $SCRIPT_DIR/cleanup-selfhosted.sh"
if [[ "$RUN_MONITOR" == "true" && -x "$MONITOR" ]]; then
  exec "$MONITOR" --resource-group "$RESOURCE_GROUP"
fi
