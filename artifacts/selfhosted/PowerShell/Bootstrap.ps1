#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops (SELF-HOSTED) - cluster-host bootstrap (Phase 1).

.DESCRIPTION
  Runs as the cluster-host VM's Custom Script Extension. Prepares the host that
  builds the ENTIRE nested Azure Local environment (DC + 3 nodes + cluster) with
  ZERO Jumpstart dependency:
    1. Persists parameters as machine environment variables (read by Phase 2).
    2. Pools the Premium data disks into drive V: (Storage Spaces).
    3. Downloads the ApexLocalOps module + New-ApexLocalCluster.ps1 + config from
       this repo.
    4. Installs the required Az PowerShell modules and tags ApexProgress=Initializing.
    5. Configures headless autologon and registers a scheduled task that runs
       New-ApexLocalCluster.ps1 (Phase 2) at logon.
    6. Installs the Hyper-V role and reboots. After the reboot, autologon triggers
       Phase 2, which configures the internal network, waits for the two staged
       ISOs, converts them, and builds the DC + nodes + cluster.

  Idempotent: re-running skips already-completed steps.

  SECURITY NOTE (lab): the Windows password is stored as a machine environment
  variable (base64) and in the Winlogon DefaultPassword for headless autologon -
  the same lab pattern the LocalBox/SFF profiles use. This is for an isolated,
  Bastion-only lab. Do not reuse this host pattern for production credentials.
#>
param(
  [string]$adminUsername,
  [string]$adminPassword,                 # base64-encoded by the Bicep CSE
  [string]$subscriptionId,
  [string]$tenantId,
  [string]$resourceGroup,
  [string]$azureLocation,
  [string]$stagingStorageAccountName,
  [string]$isoContainerName = 'iso-images',
  [string]$logsContainerName = 'logs',
  [string]$workspaceName,
  [string]$templateBaseUrl,
  [string]$vmAutologon = 'true',
  [string]$clusterNodeCount = '3',
  [string]$nodeMemoryMB = '98304',
  [string]$nodeCpuCount = '16',
  [string]$clusterName = 'apexlocal-cluster',
  [string]$azureLocalInstanceLocation = 'westeurope',
  [string]$hciResourceProviderObjectId = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Output 'apex-localops self-hosted Bootstrap - input parameters:'
$PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -ne 'adminPassword' } | Format-Table -AutoSize | Out-String | Write-Output

$rootDir = 'C:\ApexLocal'
$logsDir = Join-Path $rootDir 'Logs'
$moduleDir = Join-Path $rootDir 'ApexLocalOps'
New-Item -ItemType Directory -Force -Path $rootDir, $logsDir, $moduleDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'Bootstrap.log') -Append

# --- Persist parameters as machine environment variables (read by Phase 2) ---
$envVars = @{
  APEX_AdminUsername          = $adminUsername
  APEX_AdminPasswordB64       = $adminPassword     # base64; decoded in-memory by Phase 2
  APEX_SubscriptionId         = $subscriptionId
  APEX_TenantId               = $tenantId
  APEX_ResourceGroup          = $resourceGroup
  APEX_AzureLocation          = $azureLocation
  APEX_StagingStorageAccount  = $stagingStorageAccountName
  APEX_IsoContainer           = $isoContainerName
  APEX_LogsContainer          = $logsContainerName
  APEX_WorkspaceName          = $workspaceName
  APEX_TemplateBaseUrl        = $templateBaseUrl
  APEX_ClusterNodeCount       = $clusterNodeCount
  APEX_NodeMemoryMB           = $nodeMemoryMB
  APEX_NodeCpuCount           = $nodeCpuCount
  APEX_ClusterName            = $clusterName
  APEX_InstanceLocation       = $azureLocalInstanceLocation
  APEX_HciRpObjectId          = $hciResourceProviderObjectId
}
foreach ($kv in $envVars.GetEnumerator()) {
  [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, [System.EnvironmentVariableTarget]::Machine)
}

# Decode the admin password (kept only in memory here).
$decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminPassword))

#######################################################################
# Download the ApexLocalOps module + Phase 2 orchestrator + config
#######################################################################
$base = $templateBaseUrl.TrimEnd('/')
$rootFiles = @{
  'ApexLocal-Config.psd1'    = 'artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1'
  'New-ApexLocalCluster.ps1' = 'artifacts/selfhosted/PowerShell/New-ApexLocalCluster.ps1'
  'azlocal.json'             = 'artifacts/selfhosted/azlocal.json'
}
foreach ($d in $rootFiles.GetEnumerator()) {
  $dest = Join-Path $rootDir $d.Key
  $url = "$base/$($d.Value)"
  Write-Output "Downloading $url -> $dest"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
}
# Module files.
$moduleFiles = @('ApexLocalOps.psd1', 'ApexLocalOps.psm1')
foreach ($mf in $moduleFiles) {
  $dest = Join-Path $moduleDir $mf
  $url = "$base/artifacts/selfhosted/PowerShell/ApexLocalOps/$mf"
  Write-Output "Downloading $url -> $dest"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
}

# Load config + module for the disk/module steps below.
Import-Module (Join-Path $moduleDir 'ApexLocalOps.psd1') -Force
$cfg = Get-ApexConfig -ConfigPath (Join-Path $rootDir 'ApexLocal-Config.psd1')
New-Item -ItemType Directory -Force -Path $cfg.Paths.IsoDir, $cfg.Paths.ToolsDir, $cfg.Paths.AnswerDir | Out-Null

#######################################################################
# Pool the Premium data disks into drive V: (Storage Spaces)
#######################################################################
if (-not (Test-Path 'V:\')) {
  Write-Output 'Pooling the data disks into drive V:...'
  $poolName = 'ApexLocalPool'
  $vdiskName = 'ApexLocalDisk'
  $canPool = Get-PhysicalDisk -CanPool $true -ErrorAction SilentlyContinue
  if ($canPool) {
    $sub = Get-StorageSubSystem
    if (-not (Get-StoragePool -FriendlyName $poolName -ErrorAction SilentlyContinue)) {
      New-StoragePool -FriendlyName $poolName -StorageSubSystemFriendlyName $sub.FriendlyName -PhysicalDisks $canPool | Out-Null
    }
    if (-not (Get-VirtualDisk -FriendlyName $vdiskName -ErrorAction SilentlyContinue)) {
      New-VirtualDisk -StoragePoolFriendlyName $poolName -FriendlyName $vdiskName `
        -ResiliencySettingName Simple -UseMaximumSize -ProvisioningType Fixed | Out-Null
    }
    $vd = Get-VirtualDisk -FriendlyName $vdiskName
    $diskNum = ($vd | Get-Disk).Number
    Initialize-Disk -Number $diskNum -PartitionStyle GPT -ErrorAction SilentlyContinue | Out-Null
    New-Partition -DiskNumber $diskNum -DriveLetter V -UseMaximumSize |
      Format-Volume -FileSystem NTFS -NewFileSystemLabel 'ApexLocal' -AllocationUnitSize 65536 -Confirm:$false | Out-Null
    Write-Output 'Data disks pooled and mounted as V:.'
  }
  else {
    Write-Output 'WARN: no poolable data disks found to create V: (continuing).'
  }
}
else {
  Write-Output 'Drive V: already present; skipping storage pool creation.'
}
New-Item -ItemType Directory -Force -Path $cfg.Paths.BaseVhdDir, $cfg.Paths.VmVhdDir, $cfg.Paths.VmDir | Out-Null

#######################################################################
# Install required Az PowerShell modules and report initial progress
#######################################################################
Write-Output 'Installing Az PowerShell modules...'
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($m in @('Az.Accounts', 'Az.Resources', 'Az.Storage')) {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Output "  installing $m"
    Install-Module -Name $m -Scope AllUsers -Force -AllowClobber
  }
}

try {
  Connect-ApexAzure | Out-Null
  Set-ApexProgress -ResourceGroup $resourceGroup -Progress 'Initializing' -Status 'Host bootstrap started' -Config $cfg
}
catch {
  Write-ApexLog "Initial Azure login/tagging failed (will retry in Phase 2): $($_.Exception.Message)" -Level WARN
}

#######################################################################
# Configure headless autologon so Phase 2 resumes after the reboot
#######################################################################
if ($vmAutologon -eq 'true') {
  Write-Output 'Configuring autologon (local account).'
  $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $winlogon 'AutoAdminLogon' '1'
  Set-ItemProperty $winlogon 'DefaultUserName' $adminUsername
  Set-ItemProperty $winlogon 'DefaultPassword' $decodedPassword
  Set-ItemProperty $winlogon 'DefaultDomainName' $env:COMPUTERNAME
}

#######################################################################
# Register the Phase 2 orchestrator to run at logon
#######################################################################
$phase2 = Join-Path $rootDir 'New-ApexLocalCluster.ps1'
$taskName = 'ApexLocalBuild'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$phase2`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $adminUsername -RunLevel Highest -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 8)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Registered scheduled task '$taskName' to run Phase 2 at logon."

#######################################################################
# Install Hyper-V (first run -> reboot; re-run -> launch Phase 2 detached)
#######################################################################
$hyperv = Get-WindowsFeature -Name Hyper-V
if (-not $hyperv.Installed) {
  Set-ApexProgress -ResourceGroup $resourceGroup -Progress 'HyperVInstalling' -Status 'Installing Hyper-V role' -Config $cfg
  Write-Output 'Installing the Hyper-V role (a reboot will follow)...'
  Install-WindowsFeature -Name Hyper-V -IncludeManagementTools | Out-Null
  Stop-Transcript
  Write-Output 'Rebooting to complete Hyper-V installation (autologon + task run Phase 2)...'
  Restart-Computer -Force
}
else {
  Set-ApexProgress -ResourceGroup $resourceGroup -Progress 'HyperVInstalled' -Status 'Hyper-V present; starting Phase 2 (detached)' -Config $cfg
  Write-Output 'Hyper-V already installed; launching Phase 2 as a detached background process (no reboot).'
  Start-Process -FilePath 'powershell.exe' `
    -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$phase2`"" `
    -WindowStyle Hidden
  Write-Output 'Phase 2 launched; the Custom Script Extension is returning now.'
  Stop-Transcript
}
