#requires -Version 5.1
<#
.SYNOPSIS
  Resume a failed self-hosted build at a named stage.
.DESCRIPTION
  Runs on the cluster host through Azure Managed Run Command. Refreshes the runtime
  artifacts to an immutable ref, restores the lab credential that failure cleanup
  deliberately scrubs, and relaunches the orchestrator at the requested stage so a
  defect costs one stage instead of a full rebuild.

  Resume reuses whatever the previous attempt already produced on V: - the staged
  ISOs, the converted base VHDXs, and any nested VMs the chosen stage does not
  rebuild. The reused lab password arrives as an encrypted protected parameter and
  is cleared before exit.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingConvertToSecureStringWithPlainText',
  '',
  Justification = 'Azure Managed Run Command supplies the lab password as an encrypted protected parameter; resume stores it only for the relaunched build and clears the plaintext before exit.'
)]
param(
  [string]$AdminPassword,
  [Parameter(Mandatory)]
  [ValidateSet('HostFabric', 'Isos', 'BaseImages', 'Router', 'DomainController',
    'ActiveDirectory', 'Nodes', 'Readiness', 'Arc', 'ClusterDeploy')]
  [string]$StartAtStage,
  [Parameter(Mandatory)] [string]$ArtifactRef,
  [string]$GitHubAccount = 'jonathan-vella',
  [string]$GitHubRepo = 'apex-localops'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$rootDir = 'C:\ApexLocal'
$orchestrator = Join-Path $rootDir 'New-ApexLocalCluster.ps1'
$baseUri = "https://raw.githubusercontent.com/$GitHubAccount/$GitHubRepo/$ArtifactRef/artifacts/selfhosted/PowerShell"

# A second build would fight the first over Hyper-V and the progress tag.
$buildMutex = New-Object System.Threading.Mutex($false, 'Global\ApexLocalBuild')
if (-not $buildMutex.WaitOne(0)) {
  $buildMutex.Dispose()
  throw 'A build or recovery process is already running on this host.'
}
$buildMutex.ReleaseMutex()
$buildMutex.Dispose()

try {
  # Refresh every runtime artifact, not just the module: exports live in the
  # manifest, and stage behaviour lives in the orchestrator and the config.
  foreach ($relativePath in @(
      'ApexLocalOps/ApexLocalOps.psm1',
      'ApexLocalOps/ApexLocalOps.psd1',
      'New-ApexLocalCluster.ps1',
      'ApexLocal-Config.psd1',
      'ModuleVersions.psd1'
    )) {
    $destination = Join-Path $rootDir ($relativePath -replace '/', '\')
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path $destinationDir)) {
      New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    }
    Invoke-WebRequest -Uri "$baseUri/$relativePath" -OutFile $destination -UseBasicParsing
    Write-Output "Refreshed $relativePath at $ArtifactRef."
  }

  # Fail here rather than minutes into the build if the refresh produced something
  # the orchestrator cannot use.
  $manifest = Import-PowerShellDataFile -Path (Join-Path $rootDir 'ApexLocalOps\ApexLocalOps.psd1')
  foreach ($requiredFunction in @('Get-ApexConfig', 'Set-ApexProgress', 'Test-ApexCommandContract')) {
    if ($manifest.FunctionsToExport -notcontains $requiredFunction) {
      throw "Refreshed manifest does not export '$requiredFunction'; check the artifact ref."
    }
  }
  if ((Get-Content -Path $orchestrator -Raw) -notmatch 'StartAtStage') {
    throw 'Refreshed orchestrator does not support stage resume; check the artifact ref.'
  }

  # Failure cleanup scrubs this deliberately, so every resumed run restores it.
  # The vault sits behind a private endpoint, so the operator's own machine cannot
  # read it; this host can, through its managed identity.
  if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    $vaultName = [Environment]::GetEnvironmentVariable('APEX_KeyVaultName', 'Machine')
    if ([string]::IsNullOrWhiteSpace($vaultName)) {
      throw 'No password supplied and APEX_KeyVaultName is not set on this host.'
    }
    $imds = ('http://169.254.169.254/metadata/identity/oauth2/token' +
      '?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net')
    $token = (Invoke-RestMethod -Uri $imds -Headers @{ Metadata = 'true' } -UseBasicParsing).access_token
    $secretUri = "https://$vaultName.vault.azure.net/secrets/lab-admin-password?api-version=7.4"
    $AdminPassword = (Invoke-RestMethod -Uri $secretUri `
        -Headers @{ Authorization = "Bearer $token" } -UseBasicParsing).value
    Write-Output "Read the lab credential from $vaultName."
  }

  [Environment]::SetEnvironmentVariable(
    'APEX_AdminPasswordB64',
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($AdminPassword)),
    'Machine')

  # -NonInteractive matters: the build runs as SYSTEM with no console, so a missing
  # mandatory parameter must fail loudly instead of blocking on an unanswerable prompt.
  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NonInteractive',
    '-File', $orchestrator,
    '-StartAtStage', $StartAtStage
  )

  Write-Output "Resumed the self-hosted build at stage '$StartAtStage' using $ArtifactRef."
}
finally {
  $AdminPassword = $null
  Remove-Variable -Name AdminPassword -ErrorAction SilentlyContinue
}
