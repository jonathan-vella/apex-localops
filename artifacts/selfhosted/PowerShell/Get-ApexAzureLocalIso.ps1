#requires -Version 5.1
<#
.SYNOPSIS
  Download the pinned Azure Local OS ISO from Microsoft's monthly release alias.
.DESCRIPTION
  Resolves the pinned aka.ms release alias, requires the final URI to use the
  official Azure Local release host, downloads to a partial file, validates the
  response length and ISO 9660 signature, then atomically promotes the ISO.

  The caller must have already accepted the Azure Local license terms in the
  Azure portal and must assert that acceptance with -AcceptLicenseTerms.
.EXAMPLE
  .\Get-ApexAzureLocalIso.ps1 -AcceptLicenseTerms
.EXAMPLE
  .\Get-ApexAzureLocalIso.ps1 -ReleaseCode 2607 -DownloadPath C:\ISOs `
    -AcceptLicenseTerms -Force
#>
[CmdletBinding()]
param(
  [ValidatePattern('^\d{4}$')] [string]$ReleaseCode = '2607',
  [string]$DownloadPath = 'C:\ISOs',
  [Parameter(Mandatory)] [switch]$AcceptLicenseTerms,
  [switch]$ResolveOnly,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
$releaseAlias = "https://aka.ms/hcireleaseimage/$ReleaseCode"
$allowedDownloadHost = 'azurestackreleases.download.prss.microsoft.com'
$minimumIsoBytes = 500MB
$destination = Join-Path $DownloadPath "AzureLocal-$ReleaseCode.iso"
$partialPath = "$destination.partial"

if (-not $AcceptLicenseTerms) {
  throw 'You must accept the Azure Local license terms in the Azure portal before downloading.'
}

function Test-ApexIsoFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [long]$ExpectedLength
  )

  $file = Get-Item -LiteralPath $Path -ErrorAction Stop
  if ($file.Length -ne $ExpectedLength -or $file.Length -lt $minimumIsoBytes) {
    throw "ISO length validation failed: local=$($file.Length), expected=$ExpectedLength."
  }

  $stream = [System.IO.File]::OpenRead($file.FullName)
  try {
    $null = $stream.Seek(0x8000, [System.IO.SeekOrigin]::Begin)
    $signatureBytes = New-Object byte[] 6
    $bytesRead = $stream.Read($signatureBytes, 0, $signatureBytes.Length)
    $signature = [System.Text.Encoding]::ASCII.GetString($signatureBytes, 0, $bytesRead)
    if ($signature -notlike '*CD001*') {
      throw "ISO 9660 signature validation failed for '$Path'."
    }
  }
  finally {
    $stream.Dispose()
  }
}

function Save-ApexHttpContent {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [uri]$Uri,
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [long]$ExpectedLength
  )

  try {
    Import-Module BitsTransfer -ErrorAction Stop
    Start-BitsTransfer -Source $Uri.AbsoluteUri -Destination $Path `
      -DisplayName "Azure Local $ReleaseCode ISO" -RetryInterval 60 -RetryTimeout 86400 `
      -ErrorAction Stop
  }
  catch {
    Write-Warning "BITS download failed; using streaming HTTP: $($_.Exception.Message)"
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [System.TimeSpan]::FromHours(24)
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
      $response = $client.GetAsync(
        $Uri,
        [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
      ).GetAwaiter().GetResult()
      $null = $response.EnsureSuccessStatusCode()
      if ($response.RequestMessage.RequestUri.Host -ne $allowedDownloadHost) {
        throw "Download redirected to an unapproved host '$($response.RequestMessage.RequestUri.Host)'."
      }
      if ($response.Content.Headers.ContentLength -ne $ExpectedLength) {
        throw 'Download response length changed after release resolution.'
      }

      $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
      $outputStream = [System.IO.File]::Create($Path)
      $buffer = New-Object byte[] 1048576
      while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $outputStream.Write($buffer, 0, $bytesRead)
      }
    }
    finally {
      if ($outputStream) { $outputStream.Dispose() }
      if ($inputStream) { $inputStream.Dispose() }
      if ($response) { $response.Dispose() }
      $client.Dispose()
    }
  }
}

New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $true
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [System.TimeSpan]::FromMinutes(2)
$response = $null
try {
  $request = New-Object System.Net.Http.HttpRequestMessage(
    [System.Net.Http.HttpMethod]::Get,
    $releaseAlias
  )
  $request.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue(0, 0)
  $response = $client.SendAsync(
    $request,
    [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
  ).GetAwaiter().GetResult()
  $null = $response.EnsureSuccessStatusCode()

  $resolvedUri = $response.RequestMessage.RequestUri
  if ($resolvedUri.Scheme -ne 'https' -or $resolvedUri.Host -ne $allowedDownloadHost) {
    throw "Release alias resolved to unapproved URI '$resolvedUri'."
  }

  $contentRange = $response.Content.Headers.ContentRange
  $expectedLength = if ($contentRange -and $contentRange.Length) {
    [long]$contentRange.Length
  }
  else {
    [long]$response.Content.Headers.ContentLength
  }
  if ($expectedLength -lt $minimumIsoBytes) {
    throw "Release response length '$expectedLength' is too small for an Azure Local ISO."
  }
}
finally {
  if ($response) { $response.Dispose() }
  $client.Dispose()
  if ($request) { $request.Dispose() }
}

if ($ResolveOnly) {
  return [pscustomobject]@{
    releaseCode = $ReleaseCode
    sourceAlias = $releaseAlias
    resolvedUri = $resolvedUri.AbsoluteUri
    bytes       = $expectedLength
  }
}

if ((Test-Path -LiteralPath $destination) -and -not $Force) {
  Test-ApexIsoFile -Path $destination -ExpectedLength $expectedLength
  Write-Output "Azure Local ISO already present and valid: $destination"
}
else {
  Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  try {
    Write-Output "Downloading Azure Local release $ReleaseCode from Microsoft ($expectedLength bytes)..."
    Save-ApexHttpContent -Uri $resolvedUri -Path $partialPath -ExpectedLength $expectedLength
    Test-ApexIsoFile -Path $partialPath -ExpectedLength $expectedLength
    Move-Item -LiteralPath $partialPath -Destination $destination -Force
  }
  finally {
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  }
}

$sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{
  releaseCode = $ReleaseCode
  sourceAlias = $releaseAlias
  resolvedUri = $resolvedUri.AbsoluteUri
  path        = $destination
  bytes       = (Get-Item -LiteralPath $destination).Length
  sha256      = $sha256
}
