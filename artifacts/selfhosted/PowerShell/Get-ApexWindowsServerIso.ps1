#requires -Version 5.1
<#
.SYNOPSIS
  Download the pinned Windows Server 2025 Evaluation ISO from Microsoft.
.DESCRIPTION
  Resolves the pinned Microsoft fwlink, requires the final URI to use the
  official Microsoft software release host, downloads transactionally with
  BITS, validates the response length and ISO 9660 signature, and reports SHA-256.

  The caller must have already accepted the Windows Server Evaluation terms and
  must assert that acceptance with -AcceptEvaluationTerms.
.EXAMPLE
  .\Get-ApexWindowsServerIso.ps1 -AcceptEvaluationTerms
#>
[CmdletBinding()]
param(
  [string]$DownloadPath = 'C:\ISOs',
  [Parameter(Mandatory)] [switch]$AcceptEvaluationTerms,
  [switch]$ResolveOnly,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
$sourceAlias = 'https://go.microsoft.com/fwlink/?linkid=2293312&clcid=0x409&culture=en-us&country=us'
$allowedDownloadHost = 'software-static.download.prss.microsoft.com'
$minimumIsoBytes = 500MB
$destination = Join-Path $DownloadPath 'WindowsServer2025.iso'
$partialPath = "$destination.partial"

if (-not $AcceptEvaluationTerms) {
  throw 'You must accept the Windows Server Evaluation terms before downloading.'
}

function Test-ApexWindowsServerIso {
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

$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $true
$client = New-Object System.Net.Http.HttpClient($handler)
$client.Timeout = [System.TimeSpan]::FromMinutes(2)
$response = $null
$request = $null
try {
  $request = New-Object System.Net.Http.HttpRequestMessage(
    [System.Net.Http.HttpMethod]::Get,
    $sourceAlias
  )
  $request.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue(0, 0)
  $response = $client.SendAsync(
    $request,
    [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
  ).GetAwaiter().GetResult()
  $null = $response.EnsureSuccessStatusCode()

  $resolvedUri = $response.RequestMessage.RequestUri
  if ($resolvedUri.Scheme -ne 'https' -or $resolvedUri.Host -ne $allowedDownloadHost) {
    throw "Windows Server fwlink resolved to unapproved URI '$resolvedUri'."
  }

  $contentRange = $response.Content.Headers.ContentRange
  $expectedLength = if ($contentRange -and $contentRange.Length) {
    [long]$contentRange.Length
  }
  else {
    [long]$response.Content.Headers.ContentLength
  }
  if ($expectedLength -lt $minimumIsoBytes) {
    throw "Windows Server response length '$expectedLength' is too small for an ISO."
  }
}
finally {
  if ($response) { $response.Dispose() }
  if ($request) { $request.Dispose() }
  $client.Dispose()
}

if ($ResolveOnly) {
  return [pscustomobject]@{
    sourceAlias = $sourceAlias
    resolvedUri = $resolvedUri.AbsoluteUri
    bytes       = $expectedLength
  }
}

New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
if ((Test-Path -LiteralPath $destination) -and -not $Force) {
  Test-ApexWindowsServerIso -Path $destination -ExpectedLength $expectedLength
  Write-Output "Windows Server ISO already present and valid: $destination"
}
else {
  Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  try {
    Import-Module BitsTransfer -ErrorAction Stop
    Write-Output "Downloading Windows Server 2025 Evaluation from Microsoft ($expectedLength bytes)..."
    Start-BitsTransfer -Source $resolvedUri.AbsoluteUri -Destination $partialPath `
      -DisplayName 'Windows Server 2025 Evaluation ISO' -RetryInterval 60 -RetryTimeout 86400 `
      -ErrorAction Stop
    Test-ApexWindowsServerIso -Path $partialPath -ExpectedLength $expectedLength
    Move-Item -LiteralPath $partialPath -Destination $destination -Force
  }
  finally {
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  }
}

$sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{
  sourceAlias = $sourceAlias
  resolvedUri = $resolvedUri.AbsoluteUri
  path        = $destination
  bytes       = (Get-Item -LiteralPath $destination).Length
  sha256      = $sha256
}
