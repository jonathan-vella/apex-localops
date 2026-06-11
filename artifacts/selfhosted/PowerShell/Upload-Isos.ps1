#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops (SELF-HOSTED) - upload the Azure Local OS ISO + Windows Server ISO
  to the staging storage account. Run from the Azure jumpbox (reached over Bastion)
  so the downloads stay inside Azure.

.DESCRIPTION
  This profile has ZERO Jumpstart dependency, so it does NOT pull any prebaked VHD
  from a Microsoft/Jumpstart blob. Instead the operator downloads the two base
  images ON THE JUMPBOX and publishes them here, into the `iso-images` container,
  with the canonical blob names the cluster host watches for:

      AzureLocalOS.iso    the Azure Local OS ISO (Azure portal > Azure Local >
                          Get started > Download software; license-gated)
      WindowsServer.iso   the Windows Server 2025 ISO (used to build the nested
                          domain controller)

  The cluster host blocks until BOTH blobs are present, then pulls them with its
  managed identity and converts each to a bootable VHDX. Uses Entra auth
  (managed identity or your az/Connect-AzAccount login) - no storage keys.

  Large uploads (multi-GB) are resumable and verified by length after upload.

.EXAMPLE
  ./Upload-Isos.ps1 -StorageAccountName apexlocabc123 `
      -AzureLocalIsoPath 'C:\isos\AzureLocal.iso' `
      -WindowsServerIsoPath 'C:\isos\WindowsServer2025.iso'

.EXAMPLE
  # Upload just one (e.g. you already staged the Windows Server ISO earlier):
  ./Upload-Isos.ps1 -StorageAccountName apexlocabc123 -AzureLocalIsoPath .\AzureLocal.iso
#>
param(
  [Parameter(Mandatory)] [string]$StorageAccountName,
  [string]$Container = 'iso-images',
  [string]$AzureLocalIsoPath,
  [string]$WindowsServerIsoPath,
  [string]$AzureLocalIsoBlob = 'AzureLocalOS.iso',
  [string]$WindowsServerIsoBlob = 'WindowsServer.iso'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not $AzureLocalIsoPath -and -not $WindowsServerIsoPath) {
  throw 'Provide at least one of -AzureLocalIsoPath or -WindowsServerIsoPath.'
}

# Build the upload set from whichever paths were supplied.
$uploads = @()
if ($AzureLocalIsoPath) {
  $uploads += [pscustomobject]@{ Label = 'Azure Local OS'; Path = $AzureLocalIsoPath; Blob = $AzureLocalIsoBlob }
}
if ($WindowsServerIsoPath) {
  $uploads += [pscustomobject]@{ Label = 'Windows Server'; Path = $WindowsServerIsoPath; Blob = $WindowsServerIsoBlob }
}

foreach ($u in $uploads) {
  if (-not (Test-Path -LiteralPath $u.Path)) { throw "File not found: $($u.Path)" }
  $ext = [System.IO.Path]::GetExtension($u.Path)
  if ($ext -ne '.iso') {
    Write-Warning "$($u.Label): '$($u.Path)' does not have a .iso extension. Continuing, but confirm it is an ISO."
  }
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop

if (-not (Get-AzContext)) {
  Write-Host 'Connecting to Azure...'
  try { Connect-AzAccount -Identity | Out-Null } catch { Connect-AzAccount | Out-Null }
}

# Entra (OAuth) data-plane context - no storage account keys.
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

foreach ($u in $uploads) {
  $sizeGB = [math]::Round((Get-Item -LiteralPath $u.Path).Length / 1GB, 2)
  Write-Host ''
  Write-Host "Uploading $($u.Label) ISO ($sizeGB GB)"
  Write-Host "  '$($u.Path)'  ->  $StorageAccountName/$Container/$($u.Blob)"
  Set-AzStorageBlobContent -File $u.Path -Container $Container -Blob $u.Blob -Context $ctx -Force | Out-Null

  # Verify by length (blob vs local file) so a truncated upload is caught here,
  # not three hours into the in-VM build.
  $local = (Get-Item -LiteralPath $u.Path).Length
  $remote = (Get-AzStorageBlob -Container $Container -Blob $u.Blob -Context $ctx).Length
  if ($local -ne $remote) {
    throw "Upload size mismatch for $($u.Blob): local=$local remote=$remote. Re-run to retry."
  }
  Write-Host "  verified ($remote bytes)."
}

Write-Host ''
Write-Host 'Done. The cluster host watcher detects the staged ISO(s) and continues the build.'
Write-Host 'Track progress from your workstation with:  scripts/monitor-selfhosted.sh'
