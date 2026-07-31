#!/usr/bin/env bash
set -euo pipefail

# Download, validate, and publish both self-hosted ISOs through ApexLocal-Mgmt.

RESOURCE_GROUP="rg-apexlocal"
VM_NAME="ApexLocal-Mgmt"
STORAGE_ACCOUNT=""
CONTAINER="iso-images"
ARTIFACT_REF=""
AZURE_LOCAL_RELEASE_CODE="2607"
ACCEPT_AZURE_LOCAL_TERMS=false
ACCEPT_WINDOWS_SERVER_TERMS=false
RUN_COMMAND_NAME="ApexLocalIsoStaging"
# Artifact source (override via env when staging from a fork).
GITHUB_ACCOUNT="${GITHUB_ACCOUNT:-jonathan-vella}"
GITHUB_REPO="${GITHUB_REPO:-apex-localops}"

usage() {
  printf '%s\n' \
    'Usage: stage-selfhosted-isos.sh --artifact-ref <immutable-sha-or-tag> [options]' \
    '  --accept-azure-local-license-terms' \
    '  --accept-windows-server-evaluation-terms' \
    '  --resource-group, -g <name>' \
    '  --vm-name <name>' \
    '  --storage-account <name>' \
    '  --container <name>' \
    '  --azure-local-release-code <YYMM>' \
    '  --help, -h'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-ref) ARTIFACT_REF="${2:?missing value}"; shift 2 ;;
    --accept-azure-local-license-terms) ACCEPT_AZURE_LOCAL_TERMS=true; shift ;;
    --accept-windows-server-evaluation-terms) ACCEPT_WINDOWS_SERVER_TERMS=true; shift ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --vm-name) VM_NAME="${2:?missing value}"; shift 2 ;;
    --storage-account) STORAGE_ACCOUNT="${2:?missing value}"; shift 2 ;;
    --container) CONTAINER="${2:?missing value}"; shift 2 ;;
    --azure-local-release-code) AZURE_LOCAL_RELEASE_CODE="${2:?missing value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$ARTIFACT_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || {
  echo 'ERROR: --artifact-ref must be an immutable candidate SHA or release tag.' >&2
  exit 2
}
[[ "$AZURE_LOCAL_RELEASE_CODE" =~ ^[0-9]{4}$ ]] || {
  echo 'ERROR: --azure-local-release-code must use YYMM format.' >&2
  exit 2
}
[[ "$ACCEPT_AZURE_LOCAL_TERMS" == "true" ]] || {
  echo 'ERROR: assert prior Azure Local license acceptance with --accept-azure-local-license-terms.' >&2
  exit 2
}
[[ "$ACCEPT_WINDOWS_SERVER_TERMS" == "true" ]] || {
  echo 'ERROR: assert prior Windows Server Evaluation terms acceptance with --accept-windows-server-evaluation-terms.' >&2
  exit 2
}

command -v az >/dev/null 2>&1 || { echo 'ERROR: Azure CLI not found.' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo 'ERROR: curl not found.' >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo 'ERROR: not logged in to Azure.' >&2; exit 1; }

if [[ -z "$STORAGE_ACCOUNT" ]]; then
  STORAGE_ACCOUNT=$(az storage account list -g "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'apexloc')].name | [0]" -o tsv)
fi
[[ -n "$STORAGE_ACCOUNT" ]] || {
  echo "ERROR: no self-hosted staging storage account found in '$RESOURCE_GROUP'." >&2
  exit 1
}

VM_LOCATION=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query location -o tsv)
TEMPLATE_BASE_URL="https://raw.githubusercontent.com/${GITHUB_ACCOUNT}/${GITHUB_REPO}/${ARTIFACT_REF}/"
SCRIPT_URI="${TEMPLATE_BASE_URL}artifacts/selfhosted/PowerShell/Stage-ApexIsos.ps1"
for path in \
  artifacts/selfhosted/PowerShell/Stage-ApexIsos.ps1 \
  artifacts/selfhosted/PowerShell/Get-ApexAzureLocalIso.ps1 \
  artifacts/selfhosted/PowerShell/Get-ApexWindowsServerIso.ps1 \
  artifacts/selfhosted/PowerShell/Upload-Isos.ps1; do
  curl --fail --silent --show-error --location --head "${TEMPLATE_BASE_URL}${path}" >/dev/null || {
    echo "ERROR: immutable staging artifact is unavailable: ${TEMPLATE_BASE_URL}${path}" >&2
    exit 1
  }
done

if az vm run-command show -g "$RESOURCE_GROUP" --vm-name "$VM_NAME" \
    --run-command-name "$RUN_COMMAND_NAME" >/dev/null 2>&1; then
  az vm run-command delete -g "$RESOURCE_GROUP" --vm-name "$VM_NAME" \
    --run-command-name "$RUN_COMMAND_NAME" --yes --output none
fi

echo "Starting unattended ISO staging on ${RESOURCE_GROUP}/${VM_NAME}..."
az vm run-command create -g "$RESOURCE_GROUP" --vm-name "$VM_NAME" \
  --run-command-name "$RUN_COMMAND_NAME" --location "$VM_LOCATION" \
  --script-uri "$SCRIPT_URI" \
  --parameters \
    StorageAccountName="$STORAGE_ACCOUNT" \
    Container="$CONTAINER" \
    TemplateBaseUrl="$TEMPLATE_BASE_URL" \
    AzureLocalReleaseCode="$AZURE_LOCAL_RELEASE_CODE" \
    AzureLocalLicenseTerms=Accepted \
    WindowsServerEvaluationTerms=Accepted \
  --async-execution true --timeout-in-seconds 21600 --output none

printf '%s\n' \
  'ISO download and publication started asynchronously.' \
  "Status: az vm run-command show -g ${RESOURCE_GROUP} --vm-name ${VM_NAME} --run-command-name ${RUN_COMMAND_NAME} -o table" \
  "Build:  $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor-selfhosted.sh -g ${RESOURCE_GROUP}"
