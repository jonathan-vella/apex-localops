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

  Both ISOs are required in one invocation. Each upload is verified by byte
  length, then a manifest containing SHA-256 and WIM/ESD image metadata is
  published last. The host will not continue without that manifest.

.EXAMPLE
  ./Upload-Isos.ps1 -StorageAccountName apexlocabc123 `
      -AzureLocalIsoPath 'C:\isos\AzureLocal.iso' `
      -WindowsServerIsoPath 'C:\isos\WindowsServer2025.iso'

#>
param(
  [Parameter(Mandatory)] [string]$StorageAccountName,
  [string]$Container = 'iso-images',
  [Parameter(Mandatory)] [string]$AzureLocalIsoPath,
  [Parameter(Mandatory)] [string]$WindowsServerIsoPath,
  [string]$AzureLocalIsoBlob = 'AzureLocalOS.iso',
  [string]$WindowsServerIsoBlob = 'WindowsServer.iso',
  [string]$ManifestBlob = 'iso-manifest.json'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$uploads = @(
  [pscustomobject]@{ Label = 'Azure Local OS'; Path = $AzureLocalIsoPath; Blob = $AzureLocalIsoBlob }
  [pscustomobject]@{ Label = 'Windows Server'; Path = $WindowsServerIsoPath; Blob = $WindowsServerIsoBlob }
)

foreach ($u in $uploads) {
  if (-not (Test-Path -LiteralPath $u.Path)) { throw "File not found: $($u.Path)" }
  $ext = [System.IO.Path]::GetExtension($u.Path)
  if ($ext -ne '.iso') {
    Write-Warning "$($u.Label): '$($u.Path)' does not have a .iso extension. Continuing, but confirm it is an ISO."
  }
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop

Write-Host 'Connecting with the jumpbox managed identity...'
$identityContext = Connect-AzAccount -Identity -ErrorAction Stop
if (-not $identityContext.Context.Account.Id) {
  throw 'Managed identity authentication did not return an account context.'
}

# Entra (OAuth) data-plane context - no storage account keys.
$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
$manifestEntries = @()

function Get-IsoImageMetadata {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$IsoPath
  )

  $mountedImage = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
  try {
    $driveLetter = ($mountedImage | Get-Volume).DriveLetter
    if (-not $driveLetter) { throw "Mounted ISO has no drive letter: $IsoPath" }

    $imagePath = Join-Path "${driveLetter}:" 'sources\install.wim'
    if (-not (Test-Path $imagePath)) {
      $imagePath = Join-Path "${driveLetter}:" 'sources\install.esd'
    }
    if (-not (Test-Path $imagePath)) {
      throw "ISO contains no sources\install.wim or install.esd: $IsoPath"
    }

    return @(
      Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop | ForEach-Object {
        [ordered]@{
          imageIndex   = $_.ImageIndex
          imageName    = $_.ImageName
          version      = $_.Version.ToString()
          architecture = $_.Architecture
        }
      }
    )
  }
  finally {
    Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
  }
}

foreach ($u in $uploads) {
  $localFile = Get-Item -LiteralPath $u.Path
  $sizeGB = [math]::Round($localFile.Length / 1GB, 2)
  $sha256 = (Get-FileHash -LiteralPath $u.Path -Algorithm SHA256).Hash.ToLowerInvariant()
  $images = @(Get-IsoImageMetadata -IsoPath $localFile.FullName)
  Write-Host ''
  Write-Host "Uploading $($u.Label) ISO ($sizeGB GB)"
  Write-Host "  '$($u.Path)'  ->  $StorageAccountName/$Container/$($u.Blob)"
  Set-AzStorageBlobContent -File $u.Path -Container $Container -Blob $u.Blob -Context $ctx -Force | Out-Null

  # Verify by length (blob vs local file) so a truncated upload is caught here,
  # not three hours into the in-VM build.
  $local = $localFile.Length
  $remote = (Get-AzStorageBlob -Container $Container -Blob $u.Blob -Context $ctx).Length
  if ($local -ne $remote) {
    throw "Upload size mismatch for $($u.Blob): local=$local remote=$remote. Re-run to retry."
  }
  Write-Host "  verified ($remote bytes)."

  $manifestEntries += [ordered]@{
    label  = $u.Label
    blob   = $u.Blob
    bytes  = $local
    sha256 = $sha256
    images = $images
  }
}

$manifest = [ordered]@{
  schemaVersion = 1
  generatedUtc  = (Get-Date).ToUniversalTime().ToString('o')
  files         = $manifestEntries
}
$manifestPath = Join-Path $env:TEMP $ManifestBlob
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
try {
  Set-AzStorageBlobContent -File $manifestPath -Container $Container -Blob $ManifestBlob `
    -Context $ctx -Force | Out-Null
}
finally {
  Remove-Item -Path $manifestPath -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Done. Published $ManifestBlob after verifying both ISO uploads."
Write-Host 'Track progress from your workstation with:  scripts/monitor-selfhosted.sh'
