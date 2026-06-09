#!/usr/bin/env bash
#
# recover-cluster.sh - Re-run ONLY the Azure Local cluster cloud deployment inside the
# client VM, without rebuilding the nested nodes.
#
# The in-VM build has two halves: (1) create + Arc-register the nested nodes
# (AzLHOST1-3), which takes ~90 min, and (2) the cluster cloud deployment
# (validate + deploy of C:\LocalBox\azlocal.json). If half (2) fails - a transient
# provider-registration race, a capacity blip, a witness/policy issue - the nodes from
# half (1) are still good. This script retries only half (2) against the already
# generated ARM files, so you don't lose the ~90 min of node-build work.
#
# It runs the retry as a SYSTEM scheduled task inside the VM (so it survives the
# run-command timeout) and writes the same status files scripts/monitor.sh reads, so you
# can watch progress with:  ./monitor.sh --once --logs
#
# Usage:
#   ./recover-cluster.sh                       # trigger the retry, then print status
#   ./recover-cluster.sh --resource-group <n>  # default: rg-localbox
#   ./recover-cluster.sh --vm-name <n>         # default: LocalBox-Client
#   ./recover-cluster.sh --help
#
# Prerequisites: az login; the VM must have completed half (1) at least once
# (C:\LocalBox\azlocal.json + azlocal.parameters.json must exist on the VM).

set -euo pipefail

RESOURCE_GROUP="rg-localbox"
VM_NAME="LocalBox-Client"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --vm-name) VM_NAME="${2:?missing value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }
az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" >/dev/null 2>&1 || {
  echo "ERROR: VM '$VM_NAME' not found in resource group '$RESOURCE_GROUP'." >&2; exit 1; }

# --- The retry logic that runs inside the VM (delivered as a SYSTEM scheduled task) ---
# Uses the VM's managed identity; writes C:\LocalBox\Logs\Recovery-status.txt + a
# transcript that monitor.sh already knows how to tail.
read -r -d '' RECOVERY_PS1 <<'PSEOF' || true
$ErrorActionPreference = 'Stop'
$stamp  = Get-Date -Format 'yyyyMMddHHmmss'
$log    = "C:\LocalBox\Logs\Recovery-ClusterDeploy-$stamp.log"
$status = "C:\LocalBox\Logs\Recovery-status.txt"
function Set-Status([string]$s) { "{0:u}  {1}" -f (Get-Date), $s | Set-Content -Path $status -Encoding utf8 }
New-Item -ItemType Directory -Force -Path 'C:\LocalBox\Logs' | Out-Null
Start-Transcript -Path $log -Force | Out-Null
Set-Status 'STARTING'
try {
    $rg = $env:resourceGroup; if (-not $rg) { $rg = 'rg-localbox' }
    $tf = 'C:\LocalBox\azlocal.json'
    $pf = 'C:\LocalBox\azlocal.parameters.json'
    if (-not (Test-Path $tf) -or -not (Test-Path $pf)) {
        Set-Status 'ERROR:generated ARM files missing'
        throw "azlocal.json / azlocal.parameters.json not found in C:\LocalBox - run the full build first."
    }
    Set-Status 'CONNECTING_MI'
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Set-Status 'VALIDATING'
    New-AzResourceGroupDeployment -Name 'localcluster-validate' -ResourceGroupName $rg `
        -TemplateFile $tf -TemplateParameterFile $pf -OutVariable v -ErrorAction Stop | Out-Null
    if ($v.ProvisioningState -ne 'Succeeded') { Set-Status "VALIDATE_FAILED:$($v.ProvisioningState)"; throw "Validation state $($v.ProvisioningState)" }
    Set-Status 'DEPLOYING'
    New-AzResourceGroupDeployment -Name 'localcluster-deploy' -ResourceGroupName $rg `
        -TemplateFile $tf -deploymentMode 'Deploy' -TemplateParameterFile $pf -OutVariable d -ErrorAction Stop | Out-Null
    if ($d.ProvisioningState -eq 'Succeeded') { Set-Status 'DEPLOY_SUCCEEDED' } else { Set-Status "DEPLOY_FAILED:$($d.ProvisioningState)" }
}
catch { Set-Status "ERROR:$($_.Exception.Message)" }
finally { Stop-Transcript | Out-Null }
PSEOF

B64=$(printf '%s' "$RECOVERY_PS1" | base64 -w0)

# --- Setup script (sent via run-command): write the retry script + start the task ---
SETUP_TEMPLATE=$(cat <<'PSEOF'
$ErrorActionPreference = 'Stop'
$dst = 'C:\LocalBox\Recovery-ClusterDeploy.ps1'
New-Item -ItemType Directory -Force -Path 'C:\LocalBox\Logs' | Out-Null
[IO.File]::WriteAllBytes($dst, [Convert]::FromBase64String('__B64__'))
$task = 'LocalBox-ClusterRecovery'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\LocalBox\Recovery-ClusterDeploy.ps1'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 8)
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $task
Start-Sleep -Seconds 6
$ti = Get-ScheduledTaskInfo -TaskName $task
'TASK_STATE='  + (Get-ScheduledTask -TaskName $task).State
'LAST_RESULT=' + $ti.LastTaskResult
if (Test-Path 'C:\LocalBox\Logs\Recovery-status.txt') { 'STATUS=' + (Get-Content 'C:\LocalBox\Logs\Recovery-status.txt' -Raw).Trim() }
PSEOF
)
SETUP_PS1=${SETUP_TEMPLATE/__B64__/$B64}

echo "Triggering cluster cloud-deployment retry on '$VM_NAME' (rg '$RESOURCE_GROUP')..."
az vm run-command invoke -g "$RESOURCE_GROUP" -n "$VM_NAME" \
  --command-id RunPowerShellScript --scripts "$SETUP_PS1" \
  --query "value[0].message" -o tsv 2>&1 | grep -E '^(TASK_STATE|LAST_RESULT|STATUS)=' || true

cat <<EOF

Retry started as the SYSTEM scheduled task 'LocalBox-ClusterRecovery' (runs 2-4 h).
LAST_RESULT 267009 means the task is still running (STILL_ACTIVE); 0 means it finished.

Watch progress (authoritative = the HCI cluster resource):
    $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor.sh --resource-group $RESOURCE_GROUP
EOF
