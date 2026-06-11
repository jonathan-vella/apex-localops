#!/usr/bin/env bash
#
# monitor-selfhosted.sh - Observe the in-VM build of the SELF-HOSTED Azure Local lab.
#
# The ARM deployment finishes in ~15-20 min, but the real work (ISO->VHDX
# conversion, nested DC + node build, cluster validate/deploy) happens INSIDE the
# cluster host over several hours. This makes that phase observable without
# Bastion/RDP by polling:
#   • the resource-group ApexProgress / ApexStatus tags (in-VM milestones), and
#   • the authoritative Azure Local cluster state via 'az stack-hci cluster list'
#     (NOT 'az resource list', which can return empty even when the cluster exists).
#
# Usage:
#   ./monitor-selfhosted.sh                       # poll until Completed (or failed)
#   ./monitor-selfhosted.sh --once                # one snapshot, then exit
#   ./monitor-selfhosted.sh --interval 120        # seconds between polls (default 180)
#   ./monitor-selfhosted.sh --logs                # also tail the in-VM build log
#   ./monitor-selfhosted.sh --resource-group <n>  # default: rg-apexlocal
#   ./monitor-selfhosted.sh --help

set -euo pipefail

RESOURCE_GROUP="rg-apexlocal"
HOST_VM="ApexLocal-Host"
INTERVAL=180
ONCE=false
TAIL_LOGS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=true; shift ;;
    --interval) INTERVAL="${2:?missing value}"; shift 2 ;;
    --logs) TAIL_LOGS=true; shift ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --host-vm) HOST_VM="${2:?missing value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

# Ensure the stack-hci CLI extension is present for the authoritative cluster check.
if ! az extension show --name stack-hci >/dev/null 2>&1; then
  az extension add --name stack-hci >/dev/null 2>&1 || true
fi

snapshot() {
  local progress status cluster_line
  progress=$(az group show -n "$RESOURCE_GROUP" --query "tags.ApexProgress" -o tsv 2>/dev/null || echo "")
  status=$(az group show -n "$RESOURCE_GROUP" --query "tags.ApexStatus" -o tsv 2>/dev/null || echo "")
  [[ -z "$progress" ]] && progress="(no tag yet)"

  echo "[$(date -u +%H:%M:%SZ)] ApexProgress=${progress}"
  [[ -n "$status" ]] && echo "             ApexStatus=${status}"

  # Authoritative Azure Local cluster state.
  cluster_line=$(az stack-hci cluster list -g "$RESOURCE_GROUP" \
    --query "[0].{prov:provisioningState, conn:status}" -o tsv 2>/dev/null || true)
  if [[ -n "$cluster_line" ]]; then
    echo "             cluster: ${cluster_line}"
  fi

  if [[ "$TAIL_LOGS" == "true" ]]; then
    echo "             --- in-VM log tail ---"
    # The $l below is a PowerShell variable inside a single-quoted script passed to
    # az vm run-command; it must NOT be expanded by bash.
    # shellcheck disable=SC2016
    az vm run-command invoke -g "$RESOURCE_GROUP" -n "$HOST_VM" \
      --command-id RunPowerShellScript \
      --scripts '$l="C:\ApexLocal\Logs\New-ApexLocalCluster.log"; if(Test-Path $l){ Get-Content $l -Tail 12 } else { "build log not started yet" }' \
      --query "value[0].message" -o tsv 2>/dev/null | sed 's/^/             /' || echo "             (run-command channel busy)"
  fi
}

# Success = ApexProgress tag Completed AND cluster Succeeded/Connected.
is_done() {
  local progress prov conn
  progress=$(az group show -n "$RESOURCE_GROUP" --query "tags.ApexProgress" -o tsv 2>/dev/null || echo "")
  [[ "$progress" == "Failed" ]] && return 0
  [[ "$progress" != "Completed" ]] && return 1
  prov=$(az stack-hci cluster list -g "$RESOURCE_GROUP" --query "[0].provisioningState" -o tsv 2>/dev/null || echo "")
  conn=$(az stack-hci cluster list -g "$RESOURCE_GROUP" --query "[0].status" -o tsv 2>/dev/null || echo "")
  [[ "$prov" == "Succeeded" && "$conn" == "Connected" ]]
}

if [[ "$ONCE" == "true" ]]; then
  snapshot
  exit 0
fi

echo "Polling every ${INTERVAL}s. Ctrl-C to stop. (Build can take several hours.)"
while true; do
  snapshot
  if is_done; then
    progress=$(az group show -n "$RESOURCE_GROUP" --query "tags.ApexProgress" -o tsv 2>/dev/null || echo "")
    echo
    if [[ "$progress" == "Failed" ]]; then
      echo "Build reported Failed. Inspect with: $0 --once --logs -g $RESOURCE_GROUP" >&2
      exit 1
    fi
    echo "Cluster is Succeeded/Connected. Done."
    exit 0
  fi
  sleep "$INTERVAL"
done
