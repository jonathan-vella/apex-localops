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
$stagingSa = [Environment]::GetEnvironmentVariable('SFF_StagingStorageAccount', 'Machine')
$container = [Environment]::GetEnvironmentVariable('SFF_StagingContainer', 'Machine')
$natDNS = [Environment]::GetEnvironmentVariable('SFF_NatDNS', 'Machine')
$hvSwitchName = [Environment]::GetEnvironmentVariable('SFF_HvSwitchName', 'Machine')
$hvSubnetPrefix = [Environment]::GetEnvironmentVariable('SFF_HvSubnetPrefix', 'Machine')
$hvGateway = [Environment]::GetEnvironmentVariable('SFF_HvGateway', 'Machine')

if (-not $hvSwitchName) { $hvSwitchName = $cfg.Network.SwitchName }
if (-not $hvSubnetPrefix) { $hvSubnetPrefix = $cfg.Network.SubnetPrefix }
if (-not $hvGateway) { $hvGateway = $cfg.Network.Gateway }

$roeBlob = $cfg.Artifacts.RoeIsoBlob
$roeZipBlob = if ($cfg.Artifacts.RoeZipBlob) { $cfg.Artifacts.RoeZipBlob } else { 'roe.zip' }
$configuratorBlobs = if ($cfg.Artifacts.ConfiguratorBlobs) { $cfg.Artifacts.ConfiguratorBlobs }
elseif ($cfg.Artifacts.ConfiguratorBlob) { @($cfg.Artifacts.ConfiguratorBlob) }
else { @('configurator.msi', 'configurator.msix') }

#######################################################################
# Remove the one-time autologon keys
#######################################################################
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
foreach ($k in @('AutoAdminLogon', 'DefaultUserName', 'DefaultPassword', 'DefaultDomainName')) {
  try { Remove-ItemProperty -Path $winlogon -Name $k -ErrorAction Stop; Write-SffLog "Removed autologon key $k" } catch { }
}

#######################################################################
# Configure the internal Hyper-V NAT + DHCP network (idempotent).
# Do this BEFORE connecting to Azure: the network needs no Azure access, and the
# managed-identity login may need to retry through RBAC propagation. Configuring the
# network first guarantees it is ready even if the Azure connection is briefly delayed.
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
}
catch {
  Write-SffLog "Network configuration failed: $($_.Exception.Message)" -Level ERROR
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'Failed' -Status "Network configuration failed: $($_.Exception.Message)" -Config $cfg
  Stop-Transcript
  throw
}

#######################################################################
# Wait for the operator-staged artifacts (Azure-initiated downloads)
#######################################################################
# Connect to Azure now (retries through RBAC propagation). Required for the storage
# polling + progress tags below. If it ultimately fails, fall back to local-drop only
# so an operator can still place files in C:\LocalSFF\incoming.
$azReady = [bool](Connect-SffAzure)
if (-not $azReady) {
  Write-SffLog "Azure connection unavailable; will watch only the local incoming folder for artifacts." -Level WARN
}
Import-Module Az.Storage -ErrorAction Stop
$incomingDir = $cfg.Paths.IncomingDir
$isoDir = $cfg.Paths.IsoDir
$toolsDir = $cfg.Paths.ToolsDir
$isoLocal = Join-Path $isoDir $roeBlob

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
  }
  catch {
    Write-SffLog "Artifact check for $BlobName failed: $($_.Exception.Message)" -Level WARN
  }
  return $false
}

Set-SffProgress -ResourceGroup $resourceGroup -Progress 'AwaitingArtifacts' -Status "Waiting for the ROE image (roe.iso or roe.zip) in $container" -Config $cfg

# Extract the ROE .iso from a downloaded archive (the portal ships the Maintenance OS as a
# ZIP that contains provision-os.iso). Returns the .iso path, or $null on failure.
function Resolve-IsoFromZip {
  param([string]$ZipPath)
  $extractDir = Join-Path $isoDir 'roe-extracted'
  try {
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Write-SffLog "Extracting $ZipPath (this can take a few minutes for a multi-GB image)..."
    Expand-Archive -Path $ZipPath -DestinationPath $extractDir -Force
    $iso = Get-ChildItem $extractDir -Recurse -Filter *.iso -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending | Select-Object -First 1
    if ($iso) { Write-SffLog "Found ISO in archive: $($iso.FullName)"; return $iso.FullName }
    Write-SffLog "No .iso found inside $ZipPath." -Level WARN
  }
  catch {
    Write-SffLog "Failed to extract ${ZipPath}: $($_.Exception.Message)" -Level WARN
  }
  return $null
}

$deadline = (Get-Date).AddHours($MaxWaitHours)
$resolvedIso = $null
$isoZipLocal = Join-Path $isoDir $roeZipBlob
while ((Get-Date) -lt $deadline) {
  # 1) A pre-extracted roe.iso wins.
  if (Get-StagedArtifact -BlobName $roeBlob -Destination $isoLocal) {
    $resolvedIso = $isoLocal; break
  }
  # 2) Otherwise accept the roe.zip archive and extract the .iso from it.
  if (Get-StagedArtifact -BlobName $roeZipBlob -Destination $isoZipLocal) {
    Set-SffProgress -ResourceGroup $resourceGroup -Progress 'ExtractingImage' -Status "Extracting $roeZipBlob" -Config $cfg
    $resolvedIso = Resolve-IsoFromZip -ZipPath $isoZipLocal
    if ($resolvedIso) { break }
  }
  Start-Sleep -Seconds $PollIntervalSeconds
}

if (-not $resolvedIso) {
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'Failed' -Status "Timed out waiting for the ROE image (roe.iso/roe.zip)" -Config $cfg
  Write-SffLog "Timed out waiting for the ROE image after $MaxWaitHours h." -Level ERROR
  Stop-Transcript
  throw "ROE image not staged within $MaxWaitHours hours."
}
Set-SffProgress -ResourceGroup $resourceGroup -Progress 'ArtifactsStaged' -Status 'ROE image ready' -Config $cfg

#######################################################################
# Configurator App (OPTIONAL). The host extracts the ownership voucher over SSH
# (Get-OwnershipVoucher-Ssh.ps1), so the Configurator is only a manual GUI fallback.
# Stage it if present (.msi or .msix), but NEVER block or fail the build on it.
#######################################################################
foreach ($cb in $configuratorBlobs) {
  $dest = Join-Path $toolsDir $cb
  if (Get-StagedArtifact -BlobName $cb -Destination $dest) {
    Write-SffLog "Configurator App staged at $dest (optional; install manually if you need the GUI fallback)."
    break
  }
}

#######################################################################
# Build, configure, and boot the nested SFF test VM
#######################################################################
& (Join-Path $rootDir 'New-SffTestVm.ps1') -IsoPath $resolvedIso

Stop-Transcript
