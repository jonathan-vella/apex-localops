<#
.SYNOPSIS
    Deploy-AzLocalWorkloads.ps1 - orchestrator for post-cluster workloads
    (Windows Server 2025 VM, SQL 2022 VM, AVD session host) on the Azure Local cluster.

.DESCRIPTION
    Runs FROM THE DEV CONTAINER (or any client) with the operator's `az` login - every
    action is a cloud/ARM call, so nothing needs to run on LocalBox-Client. Imports
    AzLocalWorkloads.psm1 and drives the requested stage(s): VM/disk/NIC/image/lnet via
    the stack-hci-vm extension (custom location + Arc), and in-guest steps via the
    Microsoft.HybridCompute machines/runCommands API. Every stage is idempotent and
    additive - safe to re-run, never modifies cluster or InfraLNET config.

    This script is HUMAN-INVOKED (directly, or via scripts/deploy-workloads.sh).
    It never self-launches and never runs as a background/autopilot job.

.PARAMETER Stage
    One of: images, network, wait, ws2025, sql, avd-host, all.
    'avd-host' installs the AVD agent and requires -RegistrationToken.
    The AVD control plane (host pool/workspace/app group) is deployed separately by the
    operator via Bicep - this script only handles the in-cluster session host.

.PARAMETER RegistrationToken
    AVD host-pool registration token (required for the 'avd-host' stage).

.PARAMETER ConfigPath
    Path to Workloads-Config.psd1 (defaults next to this script).

.PARAMETER WhatIf
    Pass through to the module functions (dry-run; prints intended actions, makes no changes).

.EXAMPLE
    ./Deploy-AzLocalWorkloads.ps1 -Stage ws2025 -WhatIf
.EXAMPLE
    ./Deploy-AzLocalWorkloads.ps1 -Stage all
.EXAMPLE
    ./Deploy-AzLocalWorkloads.ps1 -Stage avd-host -RegistrationToken <token>
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('images', 'network', 'wait', 'ws2025', 'sql', 'avd-host', 'all')]
    [string]$Stage,

    [string]$RegistrationToken,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Workloads-Config.psd1'),
    [string]$ModulePath = (Join-Path $PSScriptRoot 'AzLocalWorkloads.psm1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Load module + config ----------------------------------------------------
if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
if (-not (Test-Path $ModulePath)) { throw "Module not found: $ModulePath" }
Import-Module $ModulePath -Force
$Config = Import-PowerShellDataFile -Path $ConfigPath

function Write-Banner([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

# --- Ensure authenticated + extensions (idempotent) --------------------------
function Initialize-Context {
    Write-Banner "Context: verify operator login + extensions"
    $who = (& az account show --query 'user.name' -o tsv 2>$null)
    if ([string]::IsNullOrWhiteSpace($who)) { throw "Not logged in. Run 'az login' (operator) before this script." }
    & az account set --subscription $Config.SubscriptionId 2>&1 | Out-Null
    & az config set extension.use_dynamic_install=yes_without_prompt 2>&1 | Out-Null
    foreach ($ext in @('customlocation', 'stack-hci-vm')) {
        & az extension add --name $ext 2>&1 | Out-Null
    }
    Write-Host "  Authenticated as: $who  Subscription: $($Config.SubscriptionId)" -ForegroundColor DarkGray
    return (Resolve-CustomLocationId -Config $Config)
}

# --- Stage implementations ---------------------------------------------------
function Invoke-StageImages($cl) {
    Write-Banner "Stage: images (idempotent - skips existing)"
    foreach ($key in $Config.Images.Keys) {
        $img = $Config.Images[$key]
        Ensure-MarketplaceImage -Config $Config -ImageName $img.ImageName -Urn $img.Urn `
            -OsType $img.OsType -CustomLocationId $cl -WhatIf:$WhatIfPreference | Out-Null
    }
}

function Invoke-StageNetwork($cl) {
    Write-Banner "Stage: network (idempotent - reuses existing lnet)"
    Ensure-WorkloadLogicalNetwork -Config $Config -CustomLocationId $cl -WhatIf:$WhatIfPreference | Out-Null
}

function Invoke-StageWait {
    Write-Banner "Stage: wait (poll images to Succeeded)"
    foreach ($key in $Config.Images.Keys) {
        Wait-ImageReady -Config $Config -ImageName $Config.Images[$key].ImageName | Out-Null
    }
}

function Invoke-StageVm([string]$VmKey, $cl, [string]$pw, [int]$spIndex) {
    $vm = $Config.Vms[$VmKey]
    Write-Banner "Stage: VM '$($vm.Name)' ($VmKey)"
    New-WorkloadVm -Config $Config -Vm $vm -CustomLocationId $cl -AdminPassword $pw -StoragePathIndex $spIndex -WhatIf:$WhatIfPreference | Out-Null
    if ($vm.DomainJoin -and -not $WhatIfPreference) {
        Join-VmToDomain -Config $Config -VmName $vm.Name -AdminPassword $pw | Out-Null
    }
    return $vm.Name
}

# --- Main --------------------------------------------------------------------
# With [CmdletBinding(SupportsShouldProcess)], passing -WhatIf automatically sets the
# built-in $WhatIfPreference (defaults to $false otherwise), which flows into the
# functions below and the module's -WhatIf:$WhatIfPreference passthroughs.
$cl = Initialize-Context
$pw = $null
if ($Stage -in @('ws2025', 'sql', 'avd-host', 'all') -and -not $WhatIfPreference) {
    $pw = Resolve-AdminPassword    # from LOCALBOX_ADMIN_PASSWORD env var; never logged
}

switch ($Stage) {
    'images' { Invoke-StageImages $cl }
    'network' { Invoke-StageNetwork $cl }
    'wait' { Invoke-StageWait }
    'ws2025' { Invoke-StageVm 'WindowsServer2025' $cl $pw 0 | Out-Null }
    'sql' {
        $name = Invoke-StageVm 'Sql2022' $cl $pw 1
        if (-not $WhatIfPreference) {
            Write-Host "  (run 'sql-postconfig' after the VM finishes domain-join reboot)" -ForegroundColor DarkGray
        }
    }
    'avd-host' {
        if (-not $RegistrationToken) { throw "Stage 'avd-host' requires -RegistrationToken (from the AVD host pool)." }
        $name = Invoke-StageVm 'AvdHost' $cl $pw 2
        if (-not $WhatIfPreference) {
            Add-AvdSessionHost -Config $Config -VmName $name -RegistrationToken $RegistrationToken | Out-Null
        }
    }
    'all' {
        Invoke-StageImages $cl
        Invoke-StageNetwork $cl
        Invoke-StageWait
        Invoke-StageVm 'WindowsServer2025' $cl $pw 0 | Out-Null
        Invoke-StageVm 'Sql2022' $cl $pw 1 | Out-Null
        Write-Host "  AVD session host is intentionally NOT part of 'all' - run -Stage avd-host with a token after the control plane exists." -ForegroundColor Yellow
    }
}

Write-Banner "Stage '$Stage' complete."
