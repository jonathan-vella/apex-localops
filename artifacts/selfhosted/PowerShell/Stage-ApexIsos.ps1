#requires -Version 5.1
<#
.SYNOPSIS
  Download, verify, and publish both ISOs required by the self-hosted profile.
.DESCRIPTION
  Intended for Azure Managed Run Command on ApexLocal-Mgmt. Downloads the pinned
  first-party tools from one immutable artifact base URL, acquires both Microsoft
  ISOs after explicit terms assertions, and publishes the integrity manifest last.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$StorageAccountName,
  [string]$Container = 'iso-images',
  [Parameter(Mandatory)] [string]$TemplateBaseUrl,
  [ValidatePattern('^\d{4}$')] [string]$AzureLocalReleaseCode = '2607',
  [Parameter(Mandatory)] [ValidateSet('Accepted')] [string]$AzureLocalLicenseTerms,
  [Parameter(Mandatory)] [ValidateSet('Accepted')] [string]$WindowsServerEvaluationTerms
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$rootDir = 'C:\ApexLocal'
$isoDir = 'C:\ISOs'
$logsDir = Join-Path $rootDir 'Logs'
New-Item -ItemType Directory -Force -Path $rootDir, $isoDir, $logsDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'Stage-ApexIsos.log') -Append

try {
  if ($AzureLocalLicenseTerms -ne 'Accepted' -or
      $WindowsServerEvaluationTerms -ne 'Accepted') {
    throw 'Both Microsoft terms assertions are required for unattended staging.'
  }

  $artifactBase = $TemplateBaseUrl.TrimEnd('/')
  $tools = @(
    'Get-ApexAzureLocalIso.ps1'
    'Get-ApexWindowsServerIso.ps1'
    'Upload-Isos.ps1'
  )
  foreach ($tool in $tools) {
    $uri = "$artifactBase/artifacts/selfhosted/PowerShell/$tool"
    $destination = Join-Path $rootDir $tool
    Write-Output "Downloading immutable tool: $uri"
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $destination
  }

  $azureLocalResult = & (Join-Path $rootDir 'Get-ApexAzureLocalIso.ps1') `
    -ReleaseCode $AzureLocalReleaseCode -DownloadPath $isoDir -AcceptLicenseTerms
  $windowsServerResult = & (Join-Path $rootDir 'Get-ApexWindowsServerIso.ps1') `
    -DownloadPath $isoDir -AcceptEvaluationTerms

  $azureLocalPath = Join-Path $isoDir "AzureLocal-$AzureLocalReleaseCode.iso"
  $windowsServerPath = Join-Path $isoDir 'WindowsServer2025.iso'
  & (Join-Path $rootDir 'Upload-Isos.ps1') `
    -StorageAccountName $StorageAccountName `
    -Container $Container `
    -AzureLocalIsoPath $azureLocalPath `
    -WindowsServerIsoPath $windowsServerPath

  [pscustomobject]@{
    state             = 'Completed'
    storageAccount    = $StorageAccountName
    container         = $Container
    azureLocalRelease = $AzureLocalReleaseCode
    azureLocalSha256  = $azureLocalResult.sha256
    windowsSha256     = $windowsServerResult.sha256
  }
}
finally {
  Stop-Transcript -ErrorAction SilentlyContinue
}
