#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - provision the SFF acquisition jumpbox (LocalSFF-Mgmt).

.DESCRIPTION
  Runs as the management VM's Custom Script Extension. A stock Windows 11 marketplace
  image has none of the tooling needed to stage the ROE ISO + Configurator App, so this
  script makes the jumpbox a ready-to-use "acquisition workstation":
    1. Installs Azure CLI (gives `az storage blob upload`).
    2. Installs the Az.Accounts + Az.Storage PowerShell modules (for Publish-SffArtifacts.ps1).
    3. Downloads Publish-SffArtifacts.ps1 + SffConfig.psd1 to C:\LocalSFF\.
    4. Writes concrete, copy-paste staging instructions to the desktop (with the real
       staging storage account name baked in).

  Non-fatal by design: any tooling hiccup logs a warning and the script still exits 0, so
  it never fails the ARM deployment - the desktop instructions always land. The jumpbox's
  system-assigned identity already holds Storage Blob Data Contributor on the staging
  account, so uploads authenticate with the managed identity (no keys, no secrets).
#>
param(
  [Parameter(Mandatory)] [string]$templateBaseUrl,
  [Parameter(Mandatory)] [string]$stagingStorageAccountName,
  [string]$stagingContainer = 'sff-artifacts'
)

$ErrorActionPreference = 'Continue'   # convenience setup must never fail the deploy
$ProgressPreference = 'SilentlyContinue'

$root = 'C:\LocalSFF'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Start-Transcript -Path (Join-Path $root 'Setup-SffJumpbox.log') -Append

Write-Host "apex-localops jumpbox setup. Staging account: $stagingStorageAccountName / $stagingContainer"

# --- 1. Azure CLI ---
try {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing Azure CLI...'
    $msi = Join-Path $env:TEMP 'azure-cli.msi'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/installazurecliwindowsx64' -OutFile $msi
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msi`" /quiet /norestart"
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    Write-Host 'Azure CLI installed.'
  } else {
    Write-Host 'Azure CLI already present.'
  }
} catch {
  Write-Host "WARN: Azure CLI install failed: $($_.Exception.Message)"
}

# --- 2. Az PowerShell modules used by Publish-SffArtifacts.ps1 ---
try {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  foreach ($m in @('Az.Accounts', 'Az.Storage')) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
      Write-Host "Installing $m..."
      Install-Module -Name $m -Scope AllUsers -Force -AllowClobber
    }
  }
} catch {
  Write-Host "WARN: Az module install failed: $($_.Exception.Message)"
}

# --- 3. Download the publish helper + config to C:\LocalSFF ---
try {
  $files = @(
    @{ name = 'Publish-SffArtifacts.ps1'; path = 'artifacts/sff/PowerShell/Publish-SffArtifacts.ps1' }
    @{ name = 'SffConfig.psd1';           path = 'artifacts/sff/PowerShell/SffConfig.psd1' }
  )
  foreach ($f in $files) {
    $url = ($templateBaseUrl.TrimEnd('/') + '/' + $f.path)
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile (Join-Path $root $f.name)
    Write-Host "Downloaded $($f.name)"
  }
} catch {
  Write-Host "WARN: helper script download failed: $($_.Exception.Message)"
}

# --- 4. Concrete staging instructions on the desktop (all users) ---
$instructions = @"
==========================================================================
 Azure Local SFF - stage the ROE ISO + Configurator App (acquisition step)
==========================================================================

This jumpbox is pre-installed with Azure CLI + Az PowerShell and the
Publish-SffArtifacts.ps1 helper (in C:\LocalSFF). Its managed identity can
upload to the staging storage account, so no keys or extra login are needed.

1. Open a browser here and sign in to the Azure portal:
     https://portal.azure.com
2. Go to: Azure Arc > Operations > Machine provisioning (preview) >
     Get started > View downloads > Download all
   Save both files to this VM (e.g. the Downloads folder). Extract the ISO
   archive to get the provision/ROE .iso.

3. Upload both files to the staging container. EASIEST (uses this VM's
   managed identity automatically):

     C:\LocalSFF\Publish-SffArtifacts.ps1 ``
       -StorageAccountName $stagingStorageAccountName ``
       -Container $stagingContainer ``
       -IsoPath <path-to-roe>.iso ``
       -ConfiguratorPath <path-to-configurator>.msi

   ALTERNATIVE (Azure CLI):
     az login --identity
     az storage blob upload --account-name $stagingStorageAccountName ``
       --container-name $stagingContainer --name roe.iso ``
       --file <path-to-roe>.iso --auth-mode login
     az storage blob upload --account-name $stagingStorageAccountName ``
       --container-name $stagingContainer --name configurator.msi ``
       --file <path-to-configurator>.msi --auth-mode login

4. Back on your workstation, watch progress:  ./scripts/monitor-sff.sh
   The SFF host detects the blobs and builds the nested ROE test VM.

Canonical blob names the host watches for: roe.iso  configurator.msi
==========================================================================
"@

foreach ($desktop in @('C:\Users\Public\Desktop', (Join-Path $root 'Desktop'))) {
  try {
    New-Item -ItemType Directory -Force -Path $desktop | Out-Null
    Set-Content -Path (Join-Path $desktop 'SFF-Staging-Instructions.txt') -Value $instructions -Encoding UTF8
  } catch { }
}
Set-Content -Path (Join-Path $root 'SFF-Staging-Instructions.txt') -Value $instructions -Encoding UTF8
Write-Host 'Wrote SFF-Staging-Instructions.txt to the desktop and C:\LocalSFF.'

Stop-Transcript
exit 0
