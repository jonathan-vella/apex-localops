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

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$rootDir = 'C:\ApexLocal'
$logsDir = Join-Path $rootDir 'Logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'New-ApexLocalCluster.log') -Append

# Stop the at-logon task from firing again on subsequent logons.
Unregister-ScheduledTask -TaskName 'ApexLocalBuild' -Confirm:$false -ErrorAction SilentlyContinue

Import-Module (Join-Path $rootDir 'ApexLocalOps\ApexLocalOps.psd1') -Force
$cfg = Get-ApexConfig -ConfigPath (Join-Path $rootDir 'ApexLocal-Config.psd1')

# --- Read the deployment context from the machine environment variables ---
function Env($n) { [Environment]::GetEnvironmentVariable($n, 'Machine') }
$adminUser   = Env 'APEX_AdminUsername'
$adminPwB64  = Env 'APEX_AdminPasswordB64'
$subId       = Env 'APEX_SubscriptionId'
$tenantId    = Env 'APEX_TenantId'
$rg          = Env 'APEX_ResourceGroup'
$location    = Env 'APEX_AzureLocation'
$storageAcct = Env 'APEX_StagingStorageAccount'
$isoCont     = Env 'APEX_IsoContainer'
$logsCont    = Env 'APEX_LogsContainer'
$clusterName = Env 'APEX_ClusterName'
$instanceLoc = Env 'APEX_InstanceLocation'
$hciRpOid    = Env 'APEX_HciRpObjectId'
$nodeCount   = [int](Env 'APEX_ClusterNodeCount')
if ($nodeCount -lt 2) { $nodeCount = $cfg.Cluster.NodeCount }

# Apply CSE overrides onto the config.
$cfg.Cluster.NodeCount = $nodeCount
if (Env 'APEX_NodeMemoryMB') { $cfg.Cluster.NodeMemoryMB = [int](Env 'APEX_NodeMemoryMB') }
if (Env 'APEX_NodeCpuCount') { $cfg.Cluster.NodeCpuCount = [int](Env 'APEX_NodeCpuCount') }

# Build the credentials used for PowerShell Direct + the cluster deploy.
$adminPw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminPwB64))
$securePw = ConvertTo-SecureString $adminPw -AsPlainText -Force
$localAdminCred = New-Object System.Management.Automation.PSCredential("Administrator", $securePw)

try {
  Connect-ApexAzure -SubscriptionId $subId | Out-Null

  # 1) Host fabric ------------------------------------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'NetworkConfigured' -Status 'Creating internal switch + NAT' -Config $cfg
  New-ApexHostSwitch -SwitchName $cfg.Network.SwitchName -NatName $cfg.Network.NatName `
    -Gateway $cfg.Network.Gateway -SubnetPrefix $cfg.Network.SubnetPrefix -PrefixLength $cfg.Network.PrefixLength

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
  $azlBase = Convert-ApexIsoToVhdx -IsoPath $azlIso -VhdxPath (Join-Path $cfg.Paths.BaseVhdDir 'azurelocal-base.vhdx')
  $wsBase  = Convert-ApexIsoToVhdx -IsoPath $wsIso  -VhdxPath (Join-Path $cfg.Paths.BaseVhdDir 'windowsserver-base.vhdx') `
    -ImageName 'Windows Server 2025 Datacenter (Desktop Experience)'

  # 4) Nested domain controller ----------------------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'DomainControllerReady' -Status "Building DC $($cfg.Domain.DcHostName)" -Config $cfg
  $domainAdminCred = New-ApexDomainController -Config $cfg -LocalAdminCredential $localAdminCred `
    -SafeModePassword $securePw -WindowsServerBaseVhdx $wsBase

  # 5) Azure Local node VMs ---------------------------------------------------
  $nodes = @()
  for ($i = 1; $i -le $cfg.Cluster.NodeCount; $i++) {
    $nodes += New-ApexLocalNode -Config $cfg -Index $i -LocalAdminCredential $localAdminCred -AzureLocalBaseVhdx $azlBase
  }
  Set-ApexProgress -ResourceGroup $rg -Progress 'NodesCreated' -Status "$($nodes.Count) nodes created" -Config $cfg

  # 6) Arc-register the nodes -------------------------------------------------
  $corr = [guid]::NewGuid().ToString()
  foreach ($n in $nodes) {
    Connect-ApexNodeToArc -VmName $n.Name -Credential $localAdminCred -SubscriptionId $subId `
      -ResourceGroup $rg -TenantId $tenantId -Location $instanceLoc -ArcCorrelationId $corr
  }
  Set-ApexProgress -ResourceGroup $rg -Progress 'NodesArcConnected' -Status 'Discovering Arc node resource ids' -Config $cfg

  # Discover the Arc machine resource ids the cluster template needs.
  Start-Sleep -Seconds 60
  $arcIds = @()
  foreach ($n in $nodes) {
    $res = Get-AzResource -ResourceGroupName $rg -ResourceType 'Microsoft.HybridCompute/machines' `
      -Name $n.Name -ErrorAction SilentlyContinue
    if ($res) { $arcIds += $res.ResourceId }
  }
  if ($arcIds.Count -lt $nodes.Count) {
    Write-ApexLog "Only $($arcIds.Count)/$($nodes.Count) Arc machines discovered; the cluster deploy may need a retry." -Level WARN
  }

  # 7) Validate + deploy the cluster -----------------------------------------
  Set-ApexProgress -ResourceGroup $rg -Progress 'ClusterValidating' -Status 'Validating cluster deployment' -Config $cfg
  Invoke-ApexLocalClusterDeploy -Config $cfg -ResourceGroup $rg -ClusterName $clusterName `
    -InstanceLocation $instanceLoc -HciResourceProviderObjectId $hciRpOid -ArcNodeResourceIds $arcIds `
    -Nodes $nodes -LocalAdminCredential $localAdminCred -DomainAdminCredential $domainAdminCred `
    -TemplatePath (Join-Path $rootDir 'azlocal.json')

  Set-ApexProgress -ResourceGroup $rg -Progress 'Completed' -Status "Cluster $clusterName deploy submitted" -Config $cfg
  Write-ApexLog 'Build orchestration complete.'
}
catch {
  Write-ApexLog "BUILD FAILED: $($_.Exception.Message)" -Level ERROR
  Write-ApexLog ($_.ScriptStackTrace) -Level ERROR
  Set-ApexProgress -ResourceGroup $rg -Progress 'Failed' -Status ($_.Exception.Message) -Config $cfg
}
finally {
  if ($storageAcct) { Send-ApexLogsToStorage -StorageAccountName $storageAcct -Container $logsCont }
  Stop-Transcript
}
