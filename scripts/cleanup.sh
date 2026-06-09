#!/usr/bin/env bash
#
# cleanup.sh - Tear down the LocalBox deployment and stop all billing.
#
# Disks, Bastion, and the NAT Gateway keep billing even when the VMs are
# deallocated, so the only way to stop ALL charges is to delete the resource
# group. This script shows what will be removed, then deletes the group.
#
# It does NOT touch subscription-level resource-provider registrations or quota
# (those are free and shared), so a later redeploy needs no re-registration.
#
# Usage:
#   ./cleanup.sh                       # show resources, confirm, then delete
#   ./cleanup.sh --yes                 # delete without the confirmation prompt
#   ./cleanup.sh --no-wait             # return immediately (delete continues async)
#   ./cleanup.sh --resource-group <n>  # default: rg-localbox
#   ./cleanup.sh --help
#
# Prerequisites: az login.

set -euo pipefail

RESOURCE_GROUP="rg-localbox"
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
  echo "Resource group '$RESOURCE_GROUP' does not exist - nothing to clean up."
  exit 0
fi

echo "Subscription   : $(az account show --query name -o tsv)"
echo "Resource group : $RESOURCE_GROUP"
echo
echo "Resources to be DELETED:"
az resource list -g "$RESOURCE_GROUP" \
  --query "sort_by([].{name:name, type:type}, &type)" -o table 2>/dev/null || true
echo
echo "Note: this also removes the Azure Local instance + Arc-registered nodes created"
echo "      inside the VM. Subscription-level provider registrations are left intact."
echo

# --- Confirm before a destructive, irreversible delete ---
if [[ "$ASSUME_YES" != "true" ]]; then
  printf "Type the resource group name ('%s') to confirm deletion: " "$RESOURCE_GROUP" >&2
  IFS= read -r reply || reply=""
  if [[ "$reply" != "$RESOURCE_GROUP" ]]; then
    echo "Name did not match. Aborted."
    exit 0
  fi
fi

echo "Deleting resource group '$RESOURCE_GROUP'..."
if [[ "$NO_WAIT" == "true" ]]; then
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  echo "Deletion started (async). Track with: az group show -n $RESOURCE_GROUP"
else
  az group delete --name "$RESOURCE_GROUP" --yes
  echo "Resource group '$RESOURCE_GROUP' deleted. All billing for it has stopped."
fi
