#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - Azure Local SFF host bootstrap (Phase 1).

.DESCRIPTION
  Runs as the host VM's Custom Script Extension. Prepares the Hyper-V host that will
  build the nested Azure Local SFF test VM:
    1. Persists parameters as machine environment variables.
    2. Initializes the V: data disk (nested VHDX + ISO storage).
    3. Downloads the SFF in-VM scripts + vendored set-network.ps1 from this repo.
    4. Installs the required Az PowerShell modules and tags SffProgress=Initializing.
    5. Configures headless autologon and registers a scheduled task that runs
       Stage-SffArtifacts.ps1 (Phase 2) at logon.
    6. Installs the Hyper-V role and reboots. After the reboot, autologon triggers the
       Phase 2 watcher, which configures the internal NAT network, waits for the staged
       ROE ISO + Configurator App, then builds and boots the nested test VM.

  Idempotent: re-running skips already-completed steps.
#>
param(
  [string]$adminUsername,
  [string]$adminPassword,                 # base64-encoded by the Bicep CSE
  [string]$subscriptionId,
  [string]$tenantId,
  [string]$resourceGroup,
  [string]$azureLocation,
  [string]$stagingStorageAccountName,
  [string]$stagingContainer = 'sff-artifacts',
  [string]$keyVaultName,
  [string]$workspaceName,
  [string]$templateBaseUrl,
  [string]$vmAutologon = 'true',
  [string]$natDNS = '8.8.8.8',
  [string]$hvSwitchName = 'HV-Internal-NAT',
  [string]$hvSubnetPrefix = '192.168.200.0/24',
  [string]$hvGateway = '192.168.200.1',
  [string]$nestedVmName = 'linuxsff-vm',
  [string]$nestedVmMemoryMB = '16000',
  [string]$nestedVmCpuCount = '4',
  [string]$nestedVmDiskGB = '256'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Output 'apex-localops SFF Bootstrap - input parameters:'
$PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -ne 'adminPassword' } | Format-Table -AutoSize | Out-String | Write-Output

$rootDir = 'C:\LocalSFF'
$logsDir = Join-Path $rootDir 'Logs'
New-Item -ItemType Directory -Force -Path $rootDir, $logsDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'Bootstrap-Sff.log') -Append

# --- Persist parameters as machine environment variables (read by Phase 2) ---
$envVars = @{
  SFF_AdminUsername         = $adminUsername
  SFF_SubscriptionId        = $subscriptionId
  SFF_TenantId              = $tenantId
  SFF_ResourceGroup         = $resourceGroup
  SFF_AzureLocation         = $azureLocation
  SFF_StagingStorageAccount = $stagingStorageAccountName
  SFF_StagingContainer      = $stagingContainer
  SFF_KeyVaultName          = $keyVaultName
  SFF_WorkspaceName         = $workspaceName
  SFF_TemplateBaseUrl       = $templateBaseUrl
  SFF_NatDNS                = $natDNS
  SFF_HvSwitchName          = $hvSwitchName
  SFF_HvSubnetPrefix        = $hvSubnetPrefix
  SFF_HvGateway             = $hvGateway
  SFF_NestedVmName          = $nestedVmName
  SFF_NestedVmMemoryMB      = $nestedVmMemoryMB
  SFF_NestedVmCpuCount      = $nestedVmCpuCount
  SFF_NestedVmDiskGB        = $nestedVmDiskGB
}
foreach ($kv in $envVars.GetEnumerator()) {
  [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, [System.EnvironmentVariableTarget]::Machine)
}

# Decode the admin password (kept only in memory).
$decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminPassword))

#######################################################################
# Download SFF scripts + vendored network script from this repo
#######################################################################
$downloads = @{
  'SffConfig.psd1'            = 'artifacts/sff/PowerShell/SffConfig.psd1'
  'Sff-Common.ps1'            = 'artifacts/sff/PowerShell/Sff-Common.ps1'
  'Stage-SffArtifacts.ps1'    = 'artifacts/sff/PowerShell/Stage-SffArtifacts.ps1'
  'New-SffTestVm.ps1'         = 'artifacts/sff/PowerShell/New-SffTestVm.ps1'
  'Save-OwnershipVoucher.ps1' = 'artifacts/sff/PowerShell/Save-OwnershipVoucher.ps1'
  'Get-OwnershipVoucher-Ssh.ps1' = 'artifacts/sff/PowerShell/Get-OwnershipVoucher-Ssh.ps1'
  'set-network.ps1'           = 'artifacts/sff/vendor/set-network.ps1'
}
foreach ($d in $downloads.GetEnumerator()) {
  $dest = Join-Path $rootDir $d.Key
  $url = ($templateBaseUrl.TrimEnd('/') + '/' + $d.Value)
  Write-Output "Downloading $url -> $dest"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
}

. (Join-Path $rootDir 'Sff-Common.ps1')
$cfg = Get-SffConfig -ConfigPath (Join-Path $rootDir 'SffConfig.psd1')
New-SffDirectories -Config $cfg

#######################################################################
# Initialize the V: data disk (nested VHDX + ISO storage)
#######################################################################
if (-not (Test-Path 'V:\')) {
  Write-Output 'Initializing the data disk as drive V:'
  $raw = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' } | Sort-Object Number | Select-Object -First 1
  if ($raw) {
    $raw | Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter V -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'LocalSFF' -Confirm:$false | Out-Null
    Write-Output 'Data disk initialized as V:'
  }
  else {
    Write-Output 'WARN: no RAW data disk found to initialize as V: (continuing).'
  }
}
else {
  Write-Output 'Drive V: already present; skipping disk initialization.'
}
New-Item -ItemType Directory -Force -Path $cfg.Paths.VhdDir, $cfg.Paths.VmDir | Out-Null

#######################################################################
# Install required Az PowerShell modules and report initial progress
#######################################################################
Write-Output 'Installing Az PowerShell modules...'
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($m in @('Az.Accounts', 'Az.Resources', 'Az.Storage', 'Az.KeyVault')) {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Write-Output "  installing $m"
    Install-Module -Name $m -Scope AllUsers -Force -AllowClobber
  }
}

try {
  Connect-SffAzure | Out-Null
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'Initializing' -Status 'Host bootstrap started' -Config $cfg
}
catch {
  Write-SffLog "Initial Azure login/tagging failed (will retry in Phase 2): $($_.Exception.Message)" -Level WARN
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
  # Local (workgroup) account: the domain is the local computer name. Do NOT use an FQDN.
  Set-ItemProperty $winlogon 'DefaultDomainName' $env:COMPUTERNAME
}

#######################################################################
# Register the Phase 2 watcher to run at logon
#######################################################################
$stageScript = Join-Path $rootDir 'Stage-SffArtifacts.ps1'
$taskName = 'SffStageArtifacts'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$stageScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $adminUsername -RunLevel Highest -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 6)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Registered scheduled task '$taskName' to run Phase 2 at logon."

#######################################################################
# Install Hyper-V and reboot (autologon -> Phase 2 watcher)
#######################################################################
$hyperv = Get-WindowsFeature -Name Hyper-V
if (-not $hyperv.Installed) {
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'HyperVInstalling' -Status 'Installing Hyper-V role' -Config $cfg
  Write-Output 'Installing the Hyper-V role (a reboot will follow)...'
  Install-WindowsFeature -Name Hyper-V -IncludeManagementTools | Out-Null
  Stop-Transcript
  Write-Output 'Rebooting to complete Hyper-V installation...'
  Restart-Computer -Force
}
else {
  Write-Output 'Hyper-V already installed; starting Phase 2 directly.'
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'HyperVInstalled' -Status 'Hyper-V present' -Config $cfg
  Stop-Transcript
  & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $stageScript
}
