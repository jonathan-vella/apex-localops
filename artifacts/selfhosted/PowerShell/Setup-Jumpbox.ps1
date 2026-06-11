#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops (SELF-HOSTED) - prepare the Windows Server 2025 acquisition jumpbox.

.DESCRIPTION
  Runs as the jumpbox VM's Custom Script Extension. A stock Windows Server image
  has none of the tooling needed for the one manual step in this profile, so this:
    1. Installs Azure CLI, the Az PowerShell modules, and AzCopy.
    2. Stages Upload-Isos.ps1 to C:\ApexLocal on the jumpbox.
    3. Writes a desktop README with the exact download + upload commands, pre-filled
       with this deployment's storage account + container names.

  Idempotent: re-running skips already-installed tooling.
#>
param(
  [Parameter(Mandatory)] [string]$templateBaseUrl,
  [Parameter(Mandatory)] [string]$stagingStorageAccountName,
  [string]$isoContainerName = 'iso-images'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$rootDir = 'C:\ApexLocal'
$logsDir = Join-Path $rootDir 'Logs'
New-Item -ItemType Directory -Force -Path $rootDir, $logsDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'Setup-Jumpbox.log') -Append

Write-Output 'apex-localops self-hosted jumpbox setup starting...'

# --- Trust PSGallery + install Az modules used by Upload-Isos.ps1 ---
try {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  foreach ($m in @('Az.Accounts', 'Az.Storage')) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
      Write-Output "  installing module $m"
      Install-Module -Name $m -Scope AllUsers -Force -AllowClobber
    }
  }
}
catch {
  Write-Output "WARN: Az module install issue (continuing): $($_.Exception.Message)"
}

# --- Install Azure CLI (silent MSI) ---
try {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Output '  installing Azure CLI'
    $cli = Join-Path $env:TEMP 'AzureCLI.msi'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/installazurecliwindows' -OutFile $cli
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$cli`" /qn /norestart"
    Remove-Item $cli -Force -ErrorAction SilentlyContinue
  }
}
catch {
  Write-Output "WARN: Azure CLI install issue (continuing): $($_.Exception.Message)"
}

# --- Install AzCopy (handy for very large ISO copies) ---
try {
  $toolsDir = Join-Path $rootDir 'Tools'
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  if (-not (Test-Path (Join-Path $toolsDir 'azcopy.exe'))) {
    Write-Output '  installing AzCopy'
    $zip = Join-Path $env:TEMP 'azcopy.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile $zip
    $tmp = Join-Path $env:TEMP 'azcopy_extract'
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem -Path $tmp -Recurse -Filter 'azcopy.exe' | Select-Object -First 1
    if ($exe) { Copy-Item $exe.FullName (Join-Path $toolsDir 'azcopy.exe') -Force }
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
catch {
  Write-Output "WARN: AzCopy install issue (continuing): $($_.Exception.Message)"
}

# --- Stage Upload-Isos.ps1 from the repo ---
try {
  $dest = Join-Path $rootDir 'Upload-Isos.ps1'
  $url = ($templateBaseUrl.TrimEnd('/') + '/artifacts/selfhosted/PowerShell/Upload-Isos.ps1')
  Write-Output "  downloading $url"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
}
catch {
  Write-Output "WARN: could not stage Upload-Isos.ps1 (continuing): $($_.Exception.Message)"
}

# --- Desktop README with this deployment's exact commands ---
$readme = @"
apex-localops - Azure Local SELF-HOSTED: stage the two ISOs from this jumpbox
=============================================================================

This is the ONE manual step. Both ISOs are downloaded HERE (inside Azure) and
uploaded to the deployment's storage account. The cluster host then pulls them
with its managed identity - NO Jumpstart blob, NO prebaked VHD.

Storage account : $stagingStorageAccountName
Container       : $isoContainerName

1) Download the Azure Local OS ISO (license-gated):
   - Azure portal > search "Azure Local" > Get started > Download software
   - Accept the license, choose the recommended version, Download.
   - Save it on this jumpbox, e.g. C:\isos\AzureLocal.iso

2) Download the Windows Server 2025 ISO (evaluation is fine for a lab):
   - https://www.microsoft.com/evalcenter/  (Windows Server 2025)
   - Save it on this jumpbox, e.g. C:\isos\WindowsServer2025.iso

3) Sign in and upload BOTH (PowerShell, as administrator):

   Connect-AzAccount -Identity     # uses this jumpbox's managed identity
   C:\ApexLocal\Upload-Isos.ps1 ``
       -StorageAccountName $stagingStorageAccountName ``
       -AzureLocalIsoPath    C:\isos\AzureLocal.iso ``
       -WindowsServerIsoPath C:\isos\WindowsServer2025.iso

4) Track the build from your workstation:  scripts/monitor-selfhosted.sh
"@

try {
  $public = 'C:\Users\Public\Desktop'
  New-Item -ItemType Directory -Force -Path $public | Out-Null
  Set-Content -Path (Join-Path $public 'STAGE-ISOS-README.txt') -Value $readme -Encoding UTF8
  Set-Content -Path (Join-Path $rootDir 'STAGE-ISOS-README.txt') -Value $readme -Encoding UTF8
}
catch {
  Write-Output "WARN: could not write desktop README (continuing): $($_.Exception.Message)"
}

Write-Output 'Jumpbox setup complete. See STAGE-ISOS-README.txt on the desktop.'
Stop-Transcript
