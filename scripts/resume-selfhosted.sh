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
# Artifact source (override via env when resuming from a fork).
GITHUB_ACCOUNT="${GITHUB_ACCOUNT:-jonathan-vella}"
GITHUB_REPO="${GITHUB_REPO:-apex-localops}"

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
command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI not found." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: not logged in to Azure." >&2; exit 1; }

# The build scrubs the credential from the host whenever it fails. The vault sits
# behind a private endpoint, so this machine usually cannot read it; the host does
# that itself with its managed identity. Passing one here is only a fallback.
if [[ -z "${LOCALSELF_ADMIN_PASSWORD:-}" ]]; then
  VAULT_NAME=$(az keyvault list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || true)
  if [[ -n "$VAULT_NAME" ]]; then
    LOCALSELF_ADMIN_PASSWORD=$(az keyvault secret show --vault-name "$VAULT_NAME" \
      --name lab-admin-password --query value -o tsv 2>/dev/null || true)
    export LOCALSELF_ADMIN_PASSWORD
  fi
fi

if [[ -n "${LOCALSELF_ADMIN_PASSWORD:-}" ]]; then
  (( ${#LOCALSELF_ADMIN_PASSWORD} >= 12 && ${#LOCALSELF_ADMIN_PASSWORD} <= 123 )) || {
    echo "ERROR: LOCALSELF_ADMIN_PASSWORD must be 12-123 characters." >&2
    exit 1
  }
else
  echo "No local credential; the host will read it from the lab vault over the private endpoint."
fi
trap 'unset LOCALSELF_ADMIN_PASSWORD' EXIT

RAW_BASE="https://raw.githubusercontent.com/${GITHUB_ACCOUNT}/${GITHUB_REPO}/${ARTIFACT_REF}/artifacts/selfhosted/PowerShell"
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
RUN_COMMAND_ARGS=(-g "$RESOURCE_GROUP" --vm-name "$HOST_VM"
  --run-command-name "$RUN_COMMAND_NAME" --location "$VM_LOCATION"
  --script-uri "$SCRIPT_URI"
  --parameters StartAtStage="$START_AT_STAGE" ArtifactRef="$ARTIFACT_REF" GitHubAccount="$GITHUB_ACCOUNT" GitHubRepo="$GITHUB_REPO"
  --async-execution true --timeout-in-seconds 21600 --output none)
if [[ -n "${LOCALSELF_ADMIN_PASSWORD:-}" ]]; then
  RUN_COMMAND_ARGS+=(--protected-parameters AdminPassword="$LOCALSELF_ADMIN_PASSWORD")
fi
az vm run-command create "${RUN_COMMAND_ARGS[@]}"

# Clear the previous attempt's terminal 'Failed' tag straight away. The orchestrator
# claims it too, but not for another minute or so, and a monitor started in that
# window would otherwise read the stale tag and declare the resumed build dead.
RG_ID=$(az group show -n "$RESOURCE_GROUP" --query id -o tsv)
az tag update --resource-id "$RG_ID" --operation merge --output none \
  --tags ApexProgress=Building ApexStatus="Resume requested at stage ${START_AT_STAGE}"

printf '%s\n' \
  'Resume started asynchronously as an Azure Managed Run Command.' \
  "Status:  az vm run-command show -g ${RESOURCE_GROUP} --vm-name ${HOST_VM} --run-command-name ${RUN_COMMAND_NAME} -o table" \
  "Monitor: ${SCRIPT_DIR}/monitor-selfhosted.sh -g ${RESOURCE_GROUP}"
