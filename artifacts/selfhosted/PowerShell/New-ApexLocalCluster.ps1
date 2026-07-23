#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops (SELF-HOSTED) - nested Azure Local build orchestrator (Phase 2).

.DESCRIPTION
  Runs at logon (scheduled task 'ApexLocalBuild', registered by Bootstrap.ps1).
  Drives the clean-room, ZERO-Jumpstart build end to end using the ApexLocalOps
  module:
    1. Configure the internal Hyper-V switch + host NAT.
    2. Wait for BOTH operator-staged ISOs, then download them (managed identity).
    3. Convert each ISO into a bootable Gen2 VHDX (no prebaked VHD).
    4. Build the nested domain controller (forest + DNS + NTP authority).
    5. Build N Azure Local node VMs (static IPs, storage-intent adapters).
    6. Arc-register the nodes + stage the deployment prerequisites.
    7. Validate then deploy the Azure Local cluster (artifacts/selfhosted/azlocal.json).
  Progress is surfaced via the resource-group ApexProgress/ApexStatus tags; logs
  are uploaded to the storage 'logs' container on completion or failure.

  Re-running is safe: each ApexLocalOps step is idempotent (existing VMs/disks are
  rebuilt cleanly, present base VHDXs are reused).
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingConvertToSecureStringWithPlainText',
  '',
  Justification = 'The Azure CSE supplies the lab credential as a protected setting; this boundary converts it for PowerShell Direct and clears the persisted copy during finalization.'
)]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$rootDir = 'C:\ApexLocal'
$logsDir = Join-Path $rootDir 'Logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'New-ApexLocalCluster.log') -Append

$buildMutex = New-Object System.Threading.Mutex($false, 'Global\ApexLocalBuild')
$lockAcquired = $buildMutex.WaitOne(0)
if (-not $lockAcquired) {
  Write-Error 'Another Apex Local build process is already running.'
  Stop-Transcript
  exit 2
}

# Stop the at-logon task from firing again on subsequent logons.
Unregister-ScheduledTask -TaskName 'ApexLocalBuild' -Confirm:$false -ErrorAction SilentlyContinue

Import-Module (Join-Path $rootDir 'ApexLocalOps\ApexLocalOps.psd1') -Force
$cfg = Get-ApexConfig -ConfigPath (Join-Path $rootDir 'ApexLocal-Config.psd1')

# --- Read the deployment context from the machine environment variables ---
function Env($n) { [Environment]::GetEnvironmentVariable($n, 'Machine') }
$adminPwB64 = Env 'APEX_AdminPasswordB64'
$subId = Env 'APEX_SubscriptionId'
$tenantId = Env 'APEX_TenantId'
$rg = Env 'APEX_ResourceGroup'
$storageAcct = Env 'APEX_StagingStorageAccount'
$isoCont = Env 'APEX_IsoContainer'
$logsCont = Env 'APEX_LogsContainer'
$clusterName = Env 'APEX_ClusterName'
$instanceLoc = Env 'APEX_InstanceLocation'
$hciRpOid = Env 'APEX_HciRpObjectId'
$nodeCount = [int](Env 'APEX_ClusterNodeCount')
if ($nodeCount -ne 3) {
  throw "The self-hosted release contract requires exactly 3 nodes; received '$nodeCount'."
}

# Build the credentials used for PowerShell Direct + the cluster deploy.
$adminPw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminPwB64))
$securePw = ConvertTo-SecureString $adminPw -AsPlainText -Force
$localAdminCred = New-Object System.Management.Automation.PSCredential("Administrator", $securePw)
$buildFailed = $false

try {
  Connect-ApexAzure -SubscriptionId $subId | Out-Null

  # 1) Host fabric ------------------------------------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'NetworkConfigured' -Status 'Creating internal + NAT-uplink switches' -Config $cfg
  New-ApexHostSwitch -Network $cfg.Network

  # 2) Wait for + download both ISOs -----------------------------------------
  Wait-ApexStagedIso -StorageAccountName $storageAcct -Container $isoCont `
    -AzureLocalIsoBlob $cfg.Artifacts.AzureLocalIsoBlob -WindowsServerIsoBlob $cfg.Artifacts.WindowsServerBlob `
    -ResourceGroup $rg -Config $cfg | Out-Null
  Set-ApexProgress -ResourceGroup $rg -Progress 'IsosStaged' -Status 'Both ISOs present; downloading' -Config $cfg

  $azlIso = Get-ApexStagedIso -StorageAccountName $storageAcct -Container $isoCont `
    -Blob $cfg.Artifacts.AzureLocalIsoBlob -Destination (Join-Path $cfg.Paths.IsoDir $cfg.Artifacts.AzureLocalIsoBlob)
  $wsIso = Get-ApexStagedIso -StorageAccountName $storageAcct -Container $isoCont `
    -Blob $cfg.Artifacts.WindowsServerBlob -Destination (Join-Path $cfg.Paths.IsoDir $cfg.Artifacts.WindowsServerBlob)

  # 3) Convert both ISOs to bootable base VHDXs -------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'BaseImagesConverted' -Status 'Converting ISOs to VHDX' -Config $cfg
  $azlBase = Convert-ApexIsoToVhdx -IsoPath $azlIso -VhdxPath (Join-Path $cfg.Paths.BaseVhdDir 'azurelocal-base.vhdx') `
    -ImageIndex 1
  $wsBase = Convert-ApexIsoToVhdx -IsoPath $wsIso  -VhdxPath (Join-Path $cfg.Paths.BaseVhdDir 'windowsserver-base.vhdx') `
    -ImageName 'Windows Server 2025 Datacenter (Desktop Experience)'

  # 4) Router VM (the management subnet's gateway; built from the WS base) -----
  Set-ApexProgress -ResourceGroup $rg -Progress 'RouterReady' -Status "Building router $($cfg.Router.Name)" -Config $cfg
  New-ApexRouterVM -Config $cfg -LocalAdminCredential $localAdminCred -WindowsServerBaseVhdx $wsBase

  # 5) Nested domain controller ----------------------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'DomainControllerReady' -Status "Building DC $($cfg.Domain.DcHostName)" -Config $cfg
  $domainAdminCred = New-ApexDomainController -Config $cfg -LocalAdminCredential $localAdminCred `
    -SafeModePassword $securePw -WindowsServerBaseVhdx $wsBase

  # 6) Prepare AD with Microsoft's supported tool ----------------------------
  $lcmCredential = Initialize-ApexActiveDirectory -Config $cfg `
    -DomainAdminCredential $domainAdminCred -LcmPassword $securePw

  # 7) Azure Local node VMs ---------------------------------------------------
  $nodes = @()
  for ($i = 1; $i -le $cfg.Cluster.NodeCount; $i++) {
    $nodes += New-ApexLocalNode -Config $cfg -Index $i -LocalAdminCredential $localAdminCred -AzureLocalBaseVhdx $azlBase
  }
  Set-ApexProgress -ResourceGroup $rg -Progress 'NodesCreated' -Status "$($nodes.Count) nodes created" -Config $cfg

  # 8) Run deployment readiness validators ----------------------------------
  Invoke-ApexEnvironmentValidation -Config $cfg -SubscriptionId $subId `
    -ResourceGroup $rg -ClusterName $clusterName -Nodes $nodes `
    -LocalAdminCredential $localAdminCred -DomainAdminCredential $domainAdminCred

  # 9) Arc-register the nodes -------------------------------------------------
  foreach ($n in $nodes) {
    Connect-ApexNodeToArc -VmName $n.Name -Credential $localAdminCred -SubscriptionId $subId `
      -ResourceGroup $rg -TenantId $tenantId -Location $instanceLoc
  }
  Set-ApexProgress -ResourceGroup $rg -Progress 'NodesArcConnected' -Status 'Discovering Arc node resource ids' -Config $cfg

  # Wait for all expected Arc resources to report Connected before validation.
  $arcDeadline = (Get-Date).AddMinutes(30)
  do {
    $arcIds = @()
    foreach ($n in $nodes) {
      $res = Get-AzResource -ResourceGroupName $rg -ResourceType 'Microsoft.HybridCompute/machines' `
        -Name $n.Name -ExpandProperties -ErrorAction SilentlyContinue
      if ($res -and $res.Properties.status -eq 'Connected') {
        $arcIds += $res.ResourceId
      }
    }
    if ($arcIds.Count -ne 3) {
      Write-ApexLog "Waiting for Arc Connected state: $($arcIds.Count)/3 nodes ready."
      Start-Sleep -Seconds 30
    }
  } while ($arcIds.Count -ne 3 -and (Get-Date) -lt $arcDeadline)

  if (@($arcIds | Select-Object -Unique).Count -ne 3) {
    throw "Expected exactly 3 unique Connected Arc machines before cluster deployment; discovered $(@($arcIds | Select-Object -Unique).Count)."
  }
  if ($arcIds.Count -ne 3) {
    throw "Expected exactly 3 Arc machines before cluster deployment; discovered $($arcIds.Count)."
  }

  # 10) Validate + deploy the cluster ----------------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'ClusterValidating' -Status 'Validating cluster deployment' -Config $cfg
  Invoke-ApexLocalClusterDeploy -Config $cfg -ResourceGroup $rg -ClusterName $clusterName `
    -InstanceLocation $instanceLoc -HciResourceProviderObjectId $hciRpOid -ArcNodeResourceIds $arcIds `
    -Nodes $nodes -LocalAdminCredential $localAdminCred -DomainAdminCredential $lcmCredential `
    -TemplatePath (Join-Path $rootDir 'azlocal.json')

  Set-ApexProgress -ResourceGroup $rg -Progress 'Completed' -Status "Cluster $clusterName deployment succeeded" -Config $cfg
  Write-ApexLog 'Build orchestration complete.'
}
catch {
  $buildFailed = $true
  Write-ApexLog "BUILD FAILED: $($_.Exception.Message)" -Level ERROR
  Write-ApexLog ($_.ScriptStackTrace) -Level ERROR
  Set-ApexProgress -ResourceGroup $rg -Progress 'Failed' -Status ($_.Exception.Message) -Config $cfg
}
finally {
  try {
    Clear-ApexBootstrapSecrets -Config $cfg
  }
  catch {
    Write-ApexLog "Bootstrap secret cleanup failed: $($_.Exception.Message)" -Level ERROR
    $buildFailed = $true
  }
  Clear-Variable -Name adminPw, adminPwB64, securePw, localAdminCred, domainAdminCred, lcmCredential -ErrorAction SilentlyContinue
  if ($storageAcct) { Send-ApexLogsToStorage -StorageAccountName $storageAcct -Container $logsCont }
  Stop-Transcript
  if ($lockAcquired) { $buildMutex.ReleaseMutex() }
  $buildMutex.Dispose()
}

if ($buildFailed) {
  exit 1
}
