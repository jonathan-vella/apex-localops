#!/usr/bin/env bash
set -euo pipefail

# Resume a failed self-hosted build at a named stage instead of rebuilding from scratch.
# The lab password is sent as an encrypted Managed Run Command protected parameter.

RESOURCE_GROUP="rg-apexlocal"
HOST_VM="ApexLocal-Host"
ARTIFACT_REF=""
START_AT_STAGE=""
RUN_COMMAND_NAME="ApexLocalBuildResume"
STAGES=(HostFabric Isos BaseImages Router DomainController ActiveDirectory Nodes Readiness Arc ClusterDeploy)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf '%s\n' \
    'Usage: resume-selfhosted.sh --stage <name> --artifact-ref <immutable-sha-or-tag> [options]' \
    '  --resource-group, -g <name>' \
    '  --host-vm <name>' \
    '  --help, -h' \
    '' \
    "Stages, in order: ${STAGES[*]}" \
    '' \
    'Set LOCALSELF_ADMIN_PASSWORD before running; failure cleanup scrubs it on the host.' \
    'Resume reuses the staged ISOs and converted base VHDXs already on V:, so a fix' \
    'costs one stage rather than a full rebuild. Stages before the chosen one are' \
    'skipped and their outputs reconstructed from configuration.'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) START_AT_STAGE="${2:?missing value}"; shift 2 ;;
    --artifact-ref) ARTIFACT_REF="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --host-vm) HOST_VM="${2:?missing value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

stage_is_valid=false
for stage in "${STAGES[@]}"; do
  [[ "$stage" == "$START_AT_STAGE" ]] && stage_is_valid=true
done
if [[ "$stage_is_valid" != "true" ]]; then
  echo "ERROR: --stage must be one of: ${STAGES[*]}" >&2
  exit 2
fi

[[ "$ARTIFACT_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || {
  echo "ERROR: --artifact-ref must be an immutable candidate SHA or release tag." >&2
  exit 2
}
[[ -n "${LOCALSELF_ADMIN_PASSWORD:-}" ]] || {
  echo "ERROR: set LOCALSELF_ADMIN_PASSWORD before resuming." >&2
  exit 1
}
(( ${#LOCALSELF_ADMIN_PASSWORD} >= 12 && ${#LOCALSELF_ADMIN_PASSWORD} <= 123 )) || {
  echo "ERROR: LOCALSELF_ADMIN_PASSWORD must be 12-123 characters." >&2
  exit 1
}
trap 'unset LOCALSELF_ADMIN_PASSWORD' EXIT

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI not found." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: not logged in to Azure." >&2; exit 1; }

RAW_BASE="https://raw.githubusercontent.com/jonathan-vella/apex-localops/${ARTIFACT_REF}/artifacts/selfhosted/PowerShell"
SCRIPT_URI="${RAW_BASE}/Resume-ApexLocalCluster.ps1"

# Verify every artifact the resume will pull, before touching the host.
for artifact in Resume-ApexLocalCluster.ps1 New-ApexLocalCluster.ps1 ApexLocal-Config.psd1 \
  ModuleVersions.psd1 ApexLocalOps/ApexLocalOps.psm1 ApexLocalOps/ApexLocalOps.psd1; do
  curl --fail --silent --show-error --location --head "${RAW_BASE}/${artifact}" >/dev/null || {
    echo "ERROR: runtime artifact not reachable at the immutable ref: ${RAW_BASE}/${artifact}" >&2
    exit 1
  }
done

VM_LOCATION=$(az vm show -g "$RESOURCE_GROUP" -n "$HOST_VM" --query location -o tsv)

if az vm run-command show -g "$RESOURCE_GROUP" --vm-name "$HOST_VM" \
    --run-command-name "$RUN_COMMAND_NAME" >/dev/null 2>&1; then
  az vm run-command delete -g "$RESOURCE_GROUP" --vm-name "$HOST_VM" \
    --run-command-name "$RUN_COMMAND_NAME" --yes --output none
fi

echo "Resuming ${RESOURCE_GROUP}/${HOST_VM} at stage ${START_AT_STAGE} using ${ARTIFACT_REF}..."
az vm run-command create -g "$RESOURCE_GROUP" --vm-name "$HOST_VM" \
  --run-command-name "$RUN_COMMAND_NAME" --location "$VM_LOCATION" \
  --script-uri "$SCRIPT_URI" \
  --parameters StartAtStage="$START_AT_STAGE" ArtifactRef="$ARTIFACT_REF" \
  --protected-parameters AdminPassword="$LOCALSELF_ADMIN_PASSWORD" \
  --async-execution true --timeout-in-seconds 21600 --output none

printf '%s\n' \
  'Resume started asynchronously as an Azure Managed Run Command.' \
  "Status:  az vm run-command show -g ${RESOURCE_GROUP} --vm-name ${HOST_VM} --run-command-name ${RUN_COMMAND_NAME} -o table" \
  "Monitor: ${SCRIPT_DIR}/monitor-selfhosted.sh -g ${RESOURCE_GROUP}"
