#!/usr/bin/env bash
set -euo pipefail

# Retry only the Azure Local cloud deployment on an existing self-hosted host.
# The lab password is sent as an encrypted Managed Run Command protected parameter.

RESOURCE_GROUP="rg-apexlocal"
HOST_VM="ApexLocal-Host"
ARTIFACT_REF=""
MODE="ValidateDeploy"
RUN_COMMAND_NAME="ApexLocalClusterRecovery"
# Artifact source (override via env when recovering from a fork).
GITHUB_ACCOUNT="${GITHUB_ACCOUNT:-jonathan-vella}"
GITHUB_REPO="${GITHUB_REPO:-apex-localops}"

usage() {
  printf '%s\n' \
    'Usage: recover-selfhosted.sh --artifact-ref <immutable-sha-or-tag> [options]' \
    '  --mode <ValidateDeploy|DeployOnly>' \
    '  --resource-group, -g <name>' \
    '  --host-vm <name>' \
    '  --help, -h' \
    '' \
    'Set LOCALSELF_ADMIN_PASSWORD before running.' \
    'Use recovery only after all three nodes are Arc Connected; otherwise clean up and redeploy.'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-ref) ARTIFACT_REF="${2:?missing value}"; shift 2 ;;
    --mode) MODE="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --host-vm) HOST_VM="${2:?missing value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$MODE" == "ValidateDeploy" || "$MODE" == "DeployOnly" ]] || {
  echo "ERROR: --mode must be ValidateDeploy or DeployOnly." >&2
  exit 2
}
[[ "$ARTIFACT_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || {
  echo "ERROR: --artifact-ref must be an immutable candidate SHA or release tag." >&2
  exit 2
}
[[ -n "${LOCALSELF_ADMIN_PASSWORD:-}" ]] || {
  echo "ERROR: set LOCALSELF_ADMIN_PASSWORD before running recovery." >&2
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

VM_LOCATION=$(az vm show -g "$RESOURCE_GROUP" -n "$HOST_VM" --query location -o tsv)
SCRIPT_URI="https://raw.githubusercontent.com/${GITHUB_ACCOUNT}/${GITHUB_REPO}/${ARTIFACT_REF}/artifacts/selfhosted/PowerShell/Recover-ApexLocalCluster.ps1"
curl --fail --silent --show-error --location --head "$SCRIPT_URI" >/dev/null || {
  echo "ERROR: recovery artifact is not reachable at the immutable ref: $SCRIPT_URI" >&2
  exit 1
}

if az vm run-command show -g "$RESOURCE_GROUP" --vm-name "$HOST_VM" \
    --run-command-name "$RUN_COMMAND_NAME" >/dev/null 2>&1; then
  az vm run-command delete -g "$RESOURCE_GROUP" --vm-name "$HOST_VM" \
    --run-command-name "$RUN_COMMAND_NAME" --yes --output none
fi

echo "Starting protected cluster-only recovery on ${RESOURCE_GROUP}/${HOST_VM} in mode ${MODE}..."
az vm run-command create -g "$RESOURCE_GROUP" --vm-name "$HOST_VM" \
  --run-command-name "$RUN_COMMAND_NAME" --location "$VM_LOCATION" \
  --script-uri "$SCRIPT_URI" --parameters Mode="$MODE" \
  --protected-parameters AdminPassword="$LOCALSELF_ADMIN_PASSWORD" \
  --async-execution true --timeout-in-seconds 21600 --output none

printf '%s\n' \
  'Recovery started asynchronously as an Azure Managed Run Command.' \
  "Monitor: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor-selfhosted.sh -g ${RESOURCE_GROUP}" \
  "Command status: az vm run-command show -g ${RESOURCE_GROUP} --vm-name ${HOST_VM} --run-command-name ${RUN_COMMAND_NAME} -o table"