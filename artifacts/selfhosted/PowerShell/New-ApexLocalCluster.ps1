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
  rebuilt cleanly, present base VHDXs are reused). -StartAtStage resumes a failed
  build at a named stage so a defect costs one stage instead of a full rebuild;
  skipped stages reconstruct their outputs deterministically from configuration and
  from the artifacts already on V:.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingConvertToSecureStringWithPlainText',
  '',
  Justification = 'The Azure CSE supplies the lab credential as a protected setting; this boundary converts it for PowerShell Direct and clears the persisted copy during finalization.'
)]
[CmdletBinding()]
param(
  # Resume point. The scheduled task always uses the default, which is a full build.
  [ValidateSet('HostFabric', 'Isos', 'BaseImages', 'Router', 'DomainController',
    'ActiveDirectory', 'Nodes', 'Readiness', 'Arc', 'ClusterDeploy')]
  [string]$StartAtStage = 'HostFabric'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$stageOrder = @('HostFabric', 'Isos', 'BaseImages', 'Router', 'DomainController',
  'ActiveDirectory', 'Nodes', 'Readiness', 'Arc', 'ClusterDeploy')
$startStageIndex = [array]::IndexOf($stageOrder, $StartAtStage)

function Test-ApexStage {
  param([Parameter(Mandatory)] [string]$Name)
  $willRun = ([array]::IndexOf($stageOrder, $Name) -ge $startStageIndex)
  # Record the stage entered so a failure can name it and hand back a resume point,
  # instead of making the operator read a transcript over Bastion to find one.
  if ($willRun) { $script:currentStage = $Name }
  return $willRun
}

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
$script:currentStage = $StartAtStage

try {
  Connect-ApexAzure -SubscriptionId $subId | Out-Null

  # Claim the progress tag immediately. Without this a resumed run leaves the
  # previous attempt's terminal 'Failed' tag in place until the first stage that
  # reports, so monitoring would declare a healthy build dead.
  Set-ApexProgress -ResourceGroup $rg -Progress 'Building' `
    -Status "Build started at stage '$StartAtStage'" -Config $cfg

  # Fail in seconds if an external command or parameter does not exist, rather than
  # after tens of minutes of nested VM construction.
  Test-ApexCommandContract -Contract @{
    'New-VM'                                             = @('Path', 'Generation', 'MemoryStartupBytes', 'VHDPath', 'SwitchName')
    'Set-VM'                                             = @('SmartPagingFilePath', 'SnapshotFileLocation')
    'Get-VMSecurity'                                     = @('VMName')
    'Get-VMFirmware'                                     = @('VMName')
    'Add-VMNetworkAdapterAcl'                            = @('VMNetworkAdapter', 'Action', 'Direction', 'RemoteIPAddress')
    'Get-VMNetworkAdapterAcl'                            = @('VMNetworkAdapter')
    'Set-VMNetworkAdapterVlan'                           = @('Trunk', 'NativeVlanId', 'AllowedVlanIdList')
    'Invoke-AzStackHciConnectivityValidation'            = @('PsSession')
    'Invoke-AzStackHciSoftwareValidation'                = @('PsSession', 'Exclude')
    'Invoke-AzStackHciExternalActiveDirectoryValidation' = @('ADOUPath', 'DomainFQDN', 'NamingPrefix', 'ActiveDirectoryServer', 'ActiveDirectoryCredentials', 'ClusterName', 'PhysicalMachineNames')
    'Invoke-AzStackHciNetworkValidation'                 = @('IpPools', 'ManagementSubnetValue', 'PSSession', 'ConnectionLocalAdminCredential', 'OutputPath', 'AtcHostIntents')
    'Invoke-AzStackHciArcIntegrationValidation'          = @('SubscriptionID', 'RegistrationResourceGroupName', 'ArcResourceGroupName', 'NodeNames')
    'Invoke-AzStackHciHardwareValidation'                = @('PsSession')
  }

  # 1) Host fabric ------------------------------------------------------------
  if ($startStageIndex -gt 0) {
    Write-ApexLog "Resuming build at stage '$StartAtStage' ($($startStageIndex + 1) of $($stageOrder.Count))."
  }
  if (Test-ApexStage 'HostFabric') {
    Set-ApexProgress -ResourceGroup $rg -Progress 'NetworkConfigured' -Status 'Creating internal + NAT-uplink switches' -Config $cfg
    New-ApexHostSwitch -Network $cfg.Network
  }

  # 2) Wait for + download both ISOs -----------------------------------------
  $azlIso = Join-Path $cfg.Paths.IsoDir $cfg.Artifacts.AzureLocalIsoBlob
  $wsIso = Join-Path $cfg.Paths.IsoDir $cfg.Artifacts.WindowsServerBlob
  if (Test-ApexStage 'Isos') {
    Wait-ApexStagedIso -StorageAccountName $storageAcct -Container $isoCont `
      -AzureLocalIsoBlob $cfg.Artifacts.AzureLocalIsoBlob -WindowsServerIsoBlob $cfg.Artifacts.WindowsServerBlob `
      -ResourceGroup $rg -Config $cfg | Out-Null
    Set-ApexProgress -ResourceGroup $rg -Progress 'IsosStaged' -Status 'Both ISOs present; downloading' -Config $cfg

    $azlIso = Get-ApexStagedIso -StorageAccountName $storageAcct -Container $isoCont `
      -Blob $cfg.Artifacts.AzureLocalIsoBlob -Destination $azlIso
    $wsIso = Get-ApexStagedIso -StorageAccountName $storageAcct -Container $isoCont `
      -Blob $cfg.Artifacts.WindowsServerBlob -Destination $wsIso
  }

  # 3) Convert both ISOs to bootable base VHDXs -------------------------------
  $azlBase = Join-Path $cfg.Paths.BaseVhdDir 'azurelocal-base.vhdx'
  $wsBase = Join-Path $cfg.Paths.BaseVhdDir 'windowsserver-base.vhdx'
  if (Test-ApexStage 'BaseImages') {
    if (-not (Test-Path -LiteralPath $azlIso) -or -not (Test-Path -LiteralPath $wsIso)) {
      throw "Cannot resume at '$StartAtStage': staged ISOs are missing from $($cfg.Paths.IsoDir). Rerun with -StartAtStage 'Isos'."
    }
    Set-ApexProgress -ResourceGroup $rg -Progress 'BaseImagesConverting' -Status 'Converting ISOs to VHDX' -Config $cfg
    $azlBase = Convert-ApexIsoToVhdx -IsoPath $azlIso -VhdxPath $azlBase `
      -ImageIndex 1
    $wsBase = Convert-ApexIsoToVhdx -IsoPath $wsIso -VhdxPath $wsBase `
      -ImageName 'Windows Server 2025 Datacenter Evaluation (Desktop Experience)'
    Set-ApexProgress -ResourceGroup $rg -Progress 'BaseImagesConverted' -Status 'Both base VHDX images converted and validated' -Config $cfg
  }
  elseif (-not (Test-Path -LiteralPath $azlBase) -or -not (Test-Path -LiteralPath $wsBase)) {
    throw "Cannot resume at '$StartAtStage': base VHDX images are missing from $($cfg.Paths.BaseVhdDir). Rerun with -StartAtStage 'BaseImages'."
  }

  # 4) Router VM (the management subnet's gateway; built from the WS base) -----
  if (Test-ApexStage 'Router') {
    Set-ApexProgress -ResourceGroup $rg -Progress 'RouterReady' -Status "Building router $($cfg.Router.Name)" -Config $cfg
    New-ApexRouterVM -Config $cfg -LocalAdminCredential $localAdminCred -WindowsServerBaseVhdx $wsBase
  }

  # 5) Nested domain controller ----------------------------------------------
  # New-ApexDomainController returns exactly this credential, so a resumed run can
  # reconstruct it instead of rebuilding the forest.
  $domainAdminCred = New-Object System.Management.Automation.PSCredential(
    "$($cfg.Domain.NetBiosName)\Administrator", $securePw)
  if (Test-ApexStage 'DomainController') {
    Set-ApexProgress -ResourceGroup $rg -Progress 'DomainControllerReady' -Status "Building DC $($cfg.Domain.DcHostName)" -Config $cfg
    $domainAdminCred = New-ApexDomainController -Config $cfg -LocalAdminCredential $localAdminCred `
      -SafeModePassword $securePw -WindowsServerBaseVhdx $wsBase
  }

  # 6) Prepare AD with Microsoft's supported tool ----------------------------
  $lcmCredential = New-Object System.Management.Automation.PSCredential(
    "$($cfg.Domain.NetBiosName)\$($cfg.Domain.LcmUserName)", $securePw)
  if (Test-ApexStage 'ActiveDirectory') {
    $lcmCredential = Initialize-ApexActiveDirectory -Config $cfg `
      -DomainAdminCredential $domainAdminCred -LcmPassword $securePw
  }

  # 7) Azure Local node VMs ---------------------------------------------------
  $nodes = @()
  if (Test-ApexStage 'Nodes') {
    for ($i = 1; $i -le $cfg.Cluster.NodeCount; $i++) {
      $nodes += New-ApexLocalNode -Config $cfg -Index $i -LocalAdminCredential $localAdminCred -AzureLocalBaseVhdx $azlBase
    }
    Set-ApexProgress -ResourceGroup $rg -Progress 'NodesCreated' -Status "$($nodes.Count) nodes created" -Config $cfg
  }
  else {
    # Node identity is deterministic: name prefix plus index, and NodeStartIp
    # incremented by (index - 1), matching New-ApexLocalNode.
    $startOctets = $cfg.Cluster.NodeStartIp.Split('.')
    for ($i = 1; $i -le $cfg.Cluster.NodeCount; $i++) {
      $nodes += [pscustomobject]@{
        Name      = "$($cfg.Cluster.NamePrefix)$i"
        IpAddress = ('{0}.{1}.{2}.{3}' -f $startOctets[0], $startOctets[1], $startOctets[2],
          ([int]$startOctets[3] + ($i - 1)))
      }
    }
  }

  # 8) Run deployment readiness validators ----------------------------------
  if (Test-ApexStage 'Readiness') {
    Test-ApexEnvironmentReadiness -Config $cfg -SubscriptionId $subId `
      -ResourceGroup $rg -ClusterName $clusterName -Nodes $nodes `
      -LocalAdminCredential $localAdminCred -DomainAdminCredential $domainAdminCred
  }

  # 9) Arc-register the nodes -------------------------------------------------
  if (Test-ApexStage 'Arc') {
    foreach ($n in $nodes) {
      Connect-ApexNodeToArc -VmName $n.Name -Credential $localAdminCred -SubscriptionId $subId `
        -ResourceGroup $rg -TenantId $tenantId -Location $instanceLoc
    }
  }
  Set-ApexProgress -ResourceGroup $rg -Progress 'NodesArcConnected' -Status 'Discovering Arc node resource ids' -Config $cfg

  # Wait for all expected Arc resources to report Connected before validation.
  # Query the HybridCompute provider directly, NOT Get-AzResource: the generic Resources
  # API does not return Microsoft.HybridCompute/machines here, so the old lookup reported
  # 0/3 for the full 30 minutes while all three nodes were genuinely Connected.
  $arcDeadline = (Get-Date).AddMinutes(30)
  do {
    $arcIds = @()
    foreach ($n in $nodes) {
      $arcPath = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$($n.Name)"
      try {
        $response = Invoke-AzRestMethod -Method GET -Path "${arcPath}?api-version=2024-07-10" -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
          # Plain ConvertFrom-Json is safe here: unlike the Environment Checker reports
          # this payload has no keys that differ only by case.
          $machine = $response.Content | ConvertFrom-Json
          if ($machine.properties.status -eq 'Connected') {
            $arcIds += $arcPath
          }
        }
      }
      catch {
        Write-ApexLog "Arc lookup for '$($n.Name)' failed: $($_.Exception.Message)" -Level WARN
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

  # ArcIntegration can only be validated now that the Arc machines exist. Running it
  # alongside the pre-Arc validators failed on four criticals purely because none did.
  if (Test-ApexStage 'Arc') {
    Test-ApexEnvironmentReadiness -Config $cfg -SubscriptionId $subId `
      -ResourceGroup $rg -ClusterName $clusterName -Nodes $nodes `
      -LocalAdminCredential $localAdminCred -DomainAdminCredential $domainAdminCred `
      -Phase 'PostArc' -InstanceLocation $instanceLoc
  }

  # 10) Validate + deploy the cluster ----------------------------------------
  if (Test-ApexStage 'ClusterDeploy') {
    Set-ApexProgress -ResourceGroup $rg -Progress 'ClusterValidating' -Status 'Validating cluster deployment' -Config $cfg
    Start-ApexLocalClusterDeployment -Config $cfg -ResourceGroup $rg -ClusterName $clusterName `
      -InstanceLocation $instanceLoc -HciResourceProviderObjectId $hciRpOid -ArcNodeResourceIds $arcIds `
      -Nodes $nodes -LocalAdminCredential $localAdminCred -DomainAdminCredential $lcmCredential `
      -TemplatePath (Join-Path $rootDir 'azlocal.json')
  }

  Set-ApexProgress -ResourceGroup $rg -Progress 'Completed' -Status "Cluster $clusterName deployment succeeded" -Config $cfg
  Write-ApexLog 'Build orchestration complete.'
}
catch {
  $buildFailed = $true
  $failedStage = if ($script:currentStage) { $script:currentStage } else { $StartAtStage }
  Write-ApexLog "BUILD FAILED at stage '$failedStage': $($_.Exception.Message)" -Level ERROR
  Write-ApexLog ($_.ScriptStackTrace) -Level ERROR
  # The stage name is the actionable part: it is the argument to resume-selfhosted.sh.
  Set-ApexProgress -ResourceGroup $rg -Progress 'Failed' `
    -Status "Stage '$failedStage' failed: $($_.Exception.Message)" -Config $cfg
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
  try { Stop-Transcript } catch { }
  if ($storageAcct) { Send-ApexLogsToStorage -StorageAccountName $storageAcct -Container $logsCont }
  if ($lockAcquired) { $buildMutex.ReleaseMutex() }
  $buildMutex.Dispose()
}

if ($buildFailed) {
  exit 1
}
