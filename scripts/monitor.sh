#!/usr/bin/env bash
#
# monitor.sh - Observe the LocalBox in-VM Azure Local cluster build from outside the VM.
#
# The Bicep/ARM deployment finishes in ~18 min, but the real work - building the nested
# Azure Local cluster - then runs INSIDE the client VM for 2-4 hours with no Azure-visible
# deployment state. This script surfaces that phase without Bastion/RDP by reading the
# progress signals the in-VM scripts emit:
#
#   * Resource-group + VM tags  DeploymentProgress / DeploymentStatus  (milestone strings;
#     terminal values are 'Completed' on success or 'Failed' on test failure).
#   * The Microsoft.AzureStackHCI/clusters resource and its provisioningState (authoritative
#     proof the cluster actually formed).
#   * (--logs) a live tail of C:\LocalBox\Logs via `az vm run-command` (no RDP needed).
#
# Usage:
#   ./monitor.sh                       # poll every 120s until success/failure
#   ./monitor.sh --once                # print a single status snapshot and exit
#   ./monitor.sh --logs                # include an in-VM log tail each poll (slower)
#   ./monitor.sh --interval 60         # change the poll interval (seconds)
#   ./monitor.sh --strict              # treat a 'Failed' progress tag as terminal too
#   ./monitor.sh --resource-group <n>  # default: rg-localbox
#   ./monitor.sh --vm-name <n>         # default: LocalBox-Client
#   ./monitor.sh --help
#
# The Microsoft.AzureStackHCI/clusters resource provisioningState is the AUTHORITATIVE
# signal. The DeploymentProgress tag is advisory: a re-run or recovery that re-issues only
# the cluster ARM deployment does not rewrite the tag, so a stale 'Failed' can linger from
# an earlier attempt. By default this script keeps watching the cluster resource through a
# stale 'Failed' tag; pass --strict to exit on the tag alone.
#
# Prerequisites: az login. Safe to run repeatedly; read-only (except --logs, which runs a
# read-only PowerShell snippet in the VM via run-command).

set -euo pipefail

RESOURCE_GROUP="rg-localbox"
VM_NAME="LocalBox-Client"
INTERVAL=120
ONCE=false
WITH_LOGS=false
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=true; shift ;;
    --logs) WITH_LOGS=true; shift ;;
    --strict) STRICT=true; shift ;;
    --interval) INTERVAL="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --vm-name) VM_NAME="${2:?missing value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

START_EPOCH=$(date +%s)

# Emit a read-only PowerShell snippet that tails the newest in-VM cluster/recovery logs.
vm_log_tail() {
  local script
  script=$(cat <<'PSEOF'
$ErrorActionPreference = 'SilentlyContinue'
$d = 'C:\LocalBox\Logs'
$status = Join-Path $d 'Recovery-status.txt'
if (Test-Path $status) { 'RECOVERY-STATUS: ' + (Get-Content $status -Raw).Trim() }
$log = Get-ChildItem $d -Filter '*LocalBoxCluster*.log' -File -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $log) {
  $log = Get-ChildItem $d -Filter 'Recovery-ClusterDeploy*.log' -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime | Select-Object -Last 1
}
if ($log) {
  'LOG: ' + $log.FullName + '  (' + $log.LastWriteTime.ToString('u') + ')'
  '----- last 12 lines -----'
  Get-Content $log.FullName -Tail 12
} else { 'No cluster/recovery log found yet.' }
PSEOF
)
  az vm run-command invoke -g "$RESOURCE_GROUP" -n "$VM_NAME" \
    --command-id RunPowerShellScript --scripts "$script" \
    --query "value[0].message" -o tsv 2>/dev/null | sed 's/^/    /' || echo "    (run-command unavailable)"
}

print_snapshot() {
  local now elapsed progress status cluster cname cstate cprov
  now=$(date '+%Y-%m-%d %H:%M:%S %Z')
  elapsed=$(( ($(date +%s) - START_EPOCH) / 60 ))

  progress=$(az group show -n "$RESOURCE_GROUP" --query "tags.DeploymentProgress" -o tsv 2>/dev/null || true)
  status=$(az group show -n "$RESOURCE_GROUP" --query "tags.DeploymentStatus" -o tsv 2>/dev/null || true)
  [[ -z "$progress" || "$progress" == "None" ]] && progress="(no tag yet)"
  [[ -z "$status" || "$status" == "None" ]] && status="(no tag yet)"

  cluster=$(az resource list -g "$RESOURCE_GROUP" \
    --resource-type "Microsoft.AzureStackHCI/clusters" \
    --query "[0].{name:name, state:properties.status, prov:properties.provisioningState}" \
    -o json 2>/dev/null || echo '{}')
  cname=$(echo "$cluster" | python3 -c "import sys,json;d=json.load(sys.stdin) or {};print(d.get('name') or '-')" 2>/dev/null || echo '-')
  cstate=$(echo "$cluster" | python3 -c "import sys,json;d=json.load(sys.stdin) or {};print(d.get('state') or '-')" 2>/dev/null || echo '-')
  cprov=$(echo "$cluster" | python3 -c "import sys,json;d=json.load(sys.stdin) or {};print(d.get('prov') or '-')" 2>/dev/null || echo '-')

  echo "────────────────────────────────────────────────────────────────────"
  echo "  $now    (elapsed ${elapsed}m, polling every ${INTERVAL}s)"
  echo "  In-VM progress : $progress"
  echo "  Test status    : $status"
  echo "  HCI cluster    : name=$cname  provisioning=$cprov  status=$cstate"
  if [[ "$progress" == "Failed" && "$cprov" != "Failed" && "$cprov" != "Canceled" && "$STRICT" != "true" ]]; then
    echo "  Note           : DeploymentProgress tag is 'Failed' from the last automated test"
    echo "                   run. If a recovery/redeploy is in progress this is stale - tracking"
    echo "                   the HCI cluster resource instead. Pass --strict to exit on the tag."
  fi
  if [[ "$WITH_LOGS" == "true" ]]; then
    echo "  In-VM log tail :"
    vm_log_tail
  fi

  # Terminal-state detection (echo a sentinel the caller greps). The HCI cluster resource
  # provisioningState is authoritative; the progress tag is only terminal under --strict.
  if [[ "$cprov" == "Succeeded" || "$progress" == "Completed" ]]; then
    echo "__TERMINAL__ SUCCESS"
  elif [[ "$cprov" == "Failed" || "$cprov" == "Canceled" ]]; then
    echo "__TERMINAL__ FAILED"
  elif [[ "$progress" == "Failed" && "$STRICT" == "true" ]]; then
    echo "__TERMINAL__ FAILED"
  fi
}

echo "Monitoring LocalBox cluster build in '$RESOURCE_GROUP' (VM '$VM_NAME')."
echo "Success = HCI cluster provisioningState 'Succeeded' or DeploymentProgress 'Completed'."
echo "Press Ctrl-C to stop watching (the in-VM build keeps running regardless)."
echo

while true; do
  snapshot=$(print_snapshot)
  # Strip the sentinel line before display.
  echo "$snapshot" | grep -v '^__TERMINAL__' || true

  if echo "$snapshot" | grep -q '^__TERMINAL__ SUCCESS'; then
    echo
    echo "✅ Cluster build reached a SUCCESS state."
    exit 0
  fi
  if echo "$snapshot" | grep -q '^__TERMINAL__ FAILED'; then
    echo
    echo "❌ DeploymentProgress = 'Failed'. Inspect logs with: ./monitor.sh --once --logs"
    echo "   Full in-VM log: C:\\LocalBox\\Logs\\New-LocalBoxCluster.log"
    exit 1
  fi

  if [[ "$ONCE" == "true" ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
