#!/usr/bin/env bash
#
# cleanup-selfhosted.sh - Tear down the SELF-HOSTED Azure Local lab (stops all billing).
#
# Deletes the entire resource group. The cluster host, its 12 Premium data disks,
# Bastion, and the NAT Gateway all bill continuously even when nested VMs are off,
# so deleting the RG is the only way to reach $0. Deleting the RG also removes the
# Arc-projected Azure Local cluster + node resources it created.
#
# Usage:
#   ./cleanup-selfhosted.sh                       # confirm by typing the RG name, then delete
#   ./cleanup-selfhosted.sh --yes                 # skip the typed confirmation
#   ./cleanup-selfhosted.sh --no-wait             # return immediately (async delete)
#   ./cleanup-selfhosted.sh --resource-group <n>  # default: rg-apexlocal
#   ./cleanup-selfhosted.sh --help

set -euo pipefail

RESOURCE_GROUP="rg-apexlocal"
ASSUME_YES=false
NO_WAIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=true; shift ;;
    --no-wait) NO_WAIT=true; shift ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Resource group '$RESOURCE_GROUP' not found. Nothing to delete."
  exit 0
fi

echo "About to DELETE resource group '$RESOURCE_GROUP' and ALL resources in it:"
az resource list -g "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table 2>/dev/null || true
echo

if [[ "$ASSUME_YES" != "true" ]]; then
  printf "Type the resource group name '%s' to confirm deletion: " "$RESOURCE_GROUP" >&2
  IFS= read -r reply || reply=""
  if [[ "$reply" != "$RESOURCE_GROUP" ]]; then
    echo "Name did not match. Aborted."
    exit 0
  fi
fi

echo "Deleting resource group '$RESOURCE_GROUP' ..."
if [[ "$NO_WAIT" == "true" ]]; then
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  echo "Delete started (async). Track with: az group show -n $RESOURCE_GROUP"
else
  az group delete --name "$RESOURCE_GROUP" --yes
  echo "Resource group '$RESOURCE_GROUP' deleted."
fi
