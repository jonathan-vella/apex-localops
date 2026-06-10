#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - upload the ROE ISO + Configurator App to the SFF staging storage
  account (run from the Azure jumpbox or Azure Cloud Shell - downloads stay in Azure).

.DESCRIPTION
  After downloading the two Microsoft-owned artifacts from the Azure portal
  (Azure Arc > Machine provisioning (preview) > View downloads > Download all),
  run this from an Azure resource to publish them to the staging container with the
  canonical blob names the host watcher expects (roe.iso, configurator.msi).
  Uses Entra (managed identity or your login) auth - no storage keys.

.EXAMPLE
  ./Publish-SffArtifacts.ps1 -StorageAccountName localsffabc123 `
      -IsoPath .\roe.iso -ConfiguratorPath .\configurator.msi
#>
param(
  [Parameter(Mandatory)] [string]$StorageAccountName,
  [string]$Container = 'sff-artifacts',
  [Parameter(Mandatory)] [string]$IsoPath,
  [Parameter(Mandatory)] [string]$ConfiguratorPath,
  [string]$IsoBlobName = 'roe.iso',
  [string]$ConfiguratorBlobName = 'configurator.msi'
)

$ErrorActionPreference = 'Stop'

foreach ($p in @($IsoPath, $ConfiguratorPath)) {
  if (-not (Test-Path $p)) { throw "File not found: $p" }
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
if (-not (Get-AzContext)) {
  Write-Host 'Connecting to Azure...'
  try { Connect-AzAccount -Identity | Out-Null } catch { Connect-AzAccount | Out-Null }
}

$ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

Write-Host "Uploading '$IsoPath' -> $StorageAccountName/$Container/$IsoBlobName"
Set-AzStorageBlobContent -File $IsoPath -Container $Container -Blob $IsoBlobName -Context $ctx -Force | Out-Null

Write-Host "Uploading '$ConfiguratorPath' -> $StorageAccountName/$Container/$ConfiguratorBlobName"
Set-AzStorageBlobContent -File $ConfiguratorPath -Container $Container -Blob $ConfiguratorBlobName -Context $ctx -Force | Out-Null

Write-Host 'Done. The SFF host watcher will detect both blobs and build the nested test VM.'
Write-Host 'Track progress with:  scripts/monitor-sff.sh'
