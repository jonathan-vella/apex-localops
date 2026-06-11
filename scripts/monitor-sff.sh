#!/usr/bin/env bash
#
# monitor-sff.sh - Observe the Azure Local SFF in-VM build from outside the VM.
#
# The ARM deployment finishes quickly, but the host then installs Hyper-V, waits for
# the operator-staged ROE ISO + Configurator App, and builds the nested SFF test VM -
# a phase with no Azure-visible deployment state. This script surfaces it without
# Bastion/RDP by reading the progress signals the in-VM scripts emit:
#
#   * Resource-group + host-VM tags  SffProgress / SffStatus  (milestone strings;
#     terminal values are 'RoeSucceeded'/'VoucherStored'/'Completed' on success or
#     'Failed' on error; 'RoeTimeout' means the ROE signal was not observed in time).
#   * (--logs) a live tail of C:\LocalSFF\Logs via `az vm run-command` (no RDP needed).
#
# Usage:
#   ./monitor-sff.sh                       # poll every 120s until success/failure
#   ./monitor-sff.sh --once                # print a single status snapshot and exit
#   ./monitor-sff.sh --logs                # include an in-VM log tail each poll (slower)
#   ./monitor-sff.sh --interval 60         # change the poll interval (seconds)
#   ./monitor-sff.sh --resource-group <n>  # default: rg-sff-host-swc01
#   ./monitor-sff.sh --vm-name <n>         # default: LocalSFF-Host
#   ./monitor-sff.sh --help
#
# Prerequisites: az login. Read-only (except --logs, which runs a read-only
# PowerShell snippet in the VM via run-command).

set -euo pipefail

RESOURCE_GROUP="rg-sff-host-swc01"
VM_NAME="LocalSFF-Host"
INTERVAL=120
ONCE=false
WITH_LOGS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) ONCE=true; shift ;;
    --logs) WITH_LOGS=true; shift ;;
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

# Emit a read-only PowerShell snippet that tails the newest in-VM SFF logs.
vm_log_tail() {
  local script
  script=$(cat <<'PSEOF'
$ErrorActionPreference = 'SilentlyContinue'
$d = 'C:\LocalSFF\Logs'
$next = Join-Path $d 'NEXT-STEPS.txt'
if (Test-Path $next) { 'NEXT-STEPS: ' + (Get-Content $next -Raw).Trim() }
$log = Get-ChildItem $d -Filter '*.log' -File -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime | Select-Object -Last 1
if ($log) {
  'LOG: ' + $log.FullName + '  (' + $log.LastWriteTime.ToString('u') + ')'
  '----- last 12 lines -----'
  Get-Content $log.FullName -Tail 12
} else { 'No SFF log found yet.' }
PSEOF
)
  az vm run-command invoke -g "$RESOURCE_GROUP" -n "$VM_NAME" \
    --command-id RunPowerShellScript --scripts "$script" \
    --query "value[0].message" -o tsv 2>/dev/null | sed 's/^/    /' || echo "    (run-command unavailable)"
}

print_snapshot() {
  local now elapsed progress status
  now=$(date '+%Y-%m-%d %H:%M:%S %Z')
  elapsed=$(( ($(date +%s) - START_EPOCH) / 60 ))

  progress=$(az group show -n "$RESOURCE_GROUP" --query "tags.SffProgress" -o tsv 2>/dev/null || true)
  status=$(az group show -n "$RESOURCE_GROUP" --query "tags.SffStatus" -o tsv 2>/dev/null || true)
  [[ -z "$progress" || "$progress" == "None" ]] && progress="(no tag yet)"
  [[ -z "$status" || "$status" == "None" ]] && status="(no tag yet)"

  echo "────────────────────────────────────────────────────────────────────"
  echo "  $now    (elapsed ${elapsed}m, polling every ${INTERVAL}s)"
  echo "  SFF progress : $progress"
  echo "  SFF status   : $status"
  if [[ "$WITH_LOGS" == "true" ]]; then
    echo "  In-VM log tail :"
    vm_log_tail
  fi

  case "$progress" in
    RoeSucceeded|VoucherStored|Completed) echo "__TERMINAL__ SUCCESS" ;;
    Failed) echo "__TERMINAL__ FAILED" ;;
    RoeTimeout) echo "__TERMINAL__ TIMEOUT" ;;
  esac
}

echo "Monitoring SFF build in '$RESOURCE_GROUP' (host VM '$VM_NAME')."
echo "Success = SffProgress tag 'RoeSucceeded' (then 'VoucherStored' after the voucher step)."
echo "Press Ctrl-C to stop watching (the in-VM build keeps running regardless)."
echo

while true; do
  snapshot=$(print_snapshot)
  echo "$snapshot" | grep -v '^__TERMINAL__' || true

  if echo "$snapshot" | grep -q '^__TERMINAL__ SUCCESS'; then
    echo
    echo "✅ SFF build reached a SUCCESS state. Next: download the ownership voucher (docs/sff-runbook.md)."
    exit 0
  fi
  if echo "$snapshot" | grep -q '^__TERMINAL__ FAILED'; then
    echo
    echo "❌ SffProgress = 'Failed'. Inspect logs with: ./monitor-sff.sh --once --logs"
    echo "   Full in-VM logs: C:\\LocalSFF\\Logs"
    exit 1
  fi
  if echo "$snapshot" | grep -q '^__TERMINAL__ TIMEOUT'; then
    echo
    echo "⚠️  SffProgress = 'RoeTimeout'. The nested VM may still be healthy but the ROE"
    echo "    success string was not observed. Verify via the Hyper-V console on the host,"
    echo "    or inspect: ./monitor-sff.sh --once --logs"
    exit 2
  fi

  if [[ "$ONCE" == "true" ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
