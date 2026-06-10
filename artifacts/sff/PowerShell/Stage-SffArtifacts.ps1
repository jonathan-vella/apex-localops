#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - Azure Local SFF host bootstrap (Phase 2 watcher).

.DESCRIPTION
  Runs at logon (scheduled task registered by Bootstrap-Sff.ps1) after Hyper-V is
  installed. It:
    1. Removes the one-time autologon registry keys.
    2. Authenticates with the host managed identity.
    3. Configures the internal Hyper-V NAT + DHCP network (vendored set-network.ps1).
    4. Polls the staging storage account (and C:\LocalSFF\incoming) for the operator-
       staged roe.iso + configurator.msi - all downloads originate from Azure.
    5. Installs the Configurator App and invokes New-SffTestVm.ps1 to build, configure,
       and boot the nested SFF test VM, driving it to "ROE setup completed successfully".

  Progress is surfaced to scripts/monitor-sff.sh via the SffProgress resource-group tag.
#>
param(
  [int]$PollIntervalSeconds = 60,
  [int]$MaxWaitHours = 12
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$rootDir = 'C:\LocalSFF'
. (Join-Path $rootDir 'Sff-Common.ps1')
$cfg = Get-SffConfig -ConfigPath (Join-Path $rootDir 'SffConfig.psd1')
$logsDir = $cfg.Paths.LogsDir
Start-Transcript -Path (Join-Path $logsDir 'Stage-SffArtifacts.log') -Append

# --- Resolve context from the machine environment variables set in Phase 1 ---
$resourceGroup = [Environment]::GetEnvironmentVariable('SFF_ResourceGroup', 'Machine')
$stagingSa     = [Environment]::GetEnvironmentVariable('SFF_StagingStorageAccount', 'Machine')
$container     = [Environment]::GetEnvironmentVariable('SFF_StagingContainer', 'Machine')
$natDNS        = [Environment]::GetEnvironmentVariable('SFF_NatDNS', 'Machine')
$hvSwitchName  = [Environment]::GetEnvironmentVariable('SFF_HvSwitchName', 'Machine')
$hvSubnetPrefix= [Environment]::GetEnvironmentVariable('SFF_HvSubnetPrefix', 'Machine')
$hvGateway     = [Environment]::GetEnvironmentVariable('SFF_HvGateway', 'Machine')

if (-not $hvSwitchName)   { $hvSwitchName = $cfg.Network.SwitchName }
if (-not $hvSubnetPrefix) { $hvSubnetPrefix = $cfg.Network.SubnetPrefix }
if (-not $hvGateway)      { $hvGateway = $cfg.Network.Gateway }

$roeBlob          = $cfg.Artifacts.RoeIsoBlob
$configuratorBlob = $cfg.Artifacts.ConfiguratorBlob

#######################################################################
# Remove the one-time autologon keys
#######################################################################
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
foreach ($k in @('AutoAdminLogon', 'DefaultUserName', 'DefaultPassword', 'DefaultDomainName')) {
  try { Remove-ItemProperty -Path $winlogon -Name $k -ErrorAction Stop; Write-SffLog "Removed autologon key $k" } catch { }
}

Connect-SffAzure | Out-Null

#######################################################################
# Configure the internal Hyper-V NAT + DHCP network (idempotent)
#######################################################################
Set-SffProgress -ResourceGroup $resourceGroup -Progress 'NetworkConfiguring' -Status "Creating $hvSwitchName" -Config $cfg
try {
  $dns = ($cfg.Network.DnsServers + $natDNS) | Where-Object { $_ } | Select-Object -Unique
  & (Join-Path $rootDir 'set-network.ps1') `
      -SwitchName $hvSwitchName `
      -Mode 'WinNAT' `
      -SubnetPrefix $hvSubnetPrefix `
      -Gateway $hvGateway `
      -NatName $hvSwitchName `
      -DnsServers $dns
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'NetworkConfigured' -Status "$hvSwitchName ready" -Config $cfg
} catch {
  Write-SffLog "Network configuration failed: $($_.Exception.Message)" -Level ERROR
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'Failed' -Status "Network configuration failed: $($_.Exception.Message)" -Config $cfg
  Stop-Transcript
  throw
}

#######################################################################
# Wait for the operator-staged artifacts (Azure-initiated downloads)
#######################################################################
Import-Module Az.Storage -ErrorAction Stop
$incomingDir = $cfg.Paths.IncomingDir
$isoDir      = $cfg.Paths.IsoDir
$toolsDir    = $cfg.Paths.ToolsDir
$isoLocal          = Join-Path $isoDir $roeBlob
$configuratorLocal = Join-Path $toolsDir $configuratorBlob

function Get-StagedArtifact {
  param([string]$BlobName, [string]$Destination)
  # Local drop wins (operator may RDP to the host and place files in incoming\).
  $localDrop = Join-Path $incomingDir $BlobName
  if (Test-Path $localDrop) {
    Copy-Item -Path $localDrop -Destination $Destination -Force
    return $true
  }
  if (-not $stagingSa) { return $false }
  try {
    $ctx = New-AzStorageContext -StorageAccountName $stagingSa -UseConnectedAccount
    $blob = Get-AzStorageBlob -Container $container -Blob $BlobName -Context $ctx -ErrorAction SilentlyContinue
    if ($blob) {
      Write-SffLog "Downloading $BlobName from $stagingSa/$container"
      Get-AzStorageBlobContent -Container $container -Blob $BlobName -Destination $Destination -Context $ctx -Force | Out-Null
      return $true
    }
  } catch {
    Write-SffLog "Artifact check for $BlobName failed: $($_.Exception.Message)" -Level WARN
  }
  return $false
}

Set-SffProgress -ResourceGroup $resourceGroup -Progress 'AwaitingArtifacts' -Status "Waiting for $roeBlob + $configuratorBlob in $container" -Config $cfg
$deadline = (Get-Date).AddHours($MaxWaitHours)
$haveIso = $false
$haveConfigurator = $false
while ((Get-Date) -lt $deadline) {
  if (-not $haveIso)          { $haveIso = Get-StagedArtifact -BlobName $roeBlob -Destination $isoLocal }
  if (-not $haveConfigurator) { $haveConfigurator = Get-StagedArtifact -BlobName $configuratorBlob -Destination $configuratorLocal }
  if ($haveIso -and $haveConfigurator) { break }
  Start-Sleep -Seconds $PollIntervalSeconds
}

if (-not $haveIso) {
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'Failed' -Status "Timed out waiting for $roeBlob" -Config $cfg
  Write-SffLog "Timed out waiting for $roeBlob after $MaxWaitHours h." -Level ERROR
  Stop-Transcript
  throw "ROE ISO not staged within $MaxWaitHours hours."
}
Set-SffProgress -ResourceGroup $resourceGroup -Progress 'ArtifactsStaged' -Status 'ROE ISO downloaded' -Config $cfg

#######################################################################
# Install the Configurator App (best-effort) for the voucher step
#######################################################################
if ($haveConfigurator -and (Test-Path $configuratorLocal)) {
  try {
    Write-SffLog "Installing Configurator App from $configuratorLocal"
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$configuratorLocal`" /quiet /norestart"
  } catch {
    Write-SffLog "Configurator App silent install failed (run it manually from $configuratorLocal): $($_.Exception.Message)" -Level WARN
  }
} else {
  Write-SffLog "Configurator App not staged; the voucher step will require it on the host." -Level WARN
}

#######################################################################
# Build, configure, and boot the nested SFF test VM
#######################################################################
& (Join-Path $rootDir 'New-SffTestVm.ps1') -IsoPath $isoLocal

Stop-Transcript
