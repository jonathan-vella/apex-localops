# =============================================================================
# apex-localops - SFF shared helpers. Dot-sourced by the in-VM scripts.
# Provides: Azure login via the host managed identity, resource-group progress
# tagging (consumed by scripts/monitor-sff.sh), and consistent logging.
# =============================================================================

$ErrorActionPreference = 'Stop'

function Get-SffConfig {
  [CmdletBinding()]
  param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'SffConfig.psd1')
  )
  if (-not (Test-Path $ConfigPath)) {
    throw "SFF config file not found: $ConfigPath"
  }
  return Import-PowerShellDataFile -Path $ConfigPath
}

function Write-SffLog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO',
    [string]$LogDir = 'C:\LocalSFF\Logs'
  )
  $ts = (Get-Date).ToString('u')
  $line = "[$ts] [$Level] $Message"
  Write-Host $line
  try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    Add-Content -Path (Join-Path $LogDir 'sff-bootstrap.log') -Value $line -ErrorAction SilentlyContinue
  }
  catch {
    # Logging must never be fatal.
  }
}

function Connect-SffAzure {
  # Authenticate using the host VM's system-assigned managed identity (no secrets).
  [CmdletBinding()]
  param()
  Import-Module Az.Accounts -ErrorAction Stop
  $ctx = $null
  try { $ctx = (Get-AzContext) } catch { $ctx = $null }
  if (-not $ctx) {
    Write-SffLog "Connecting to Azure with the host managed identity..."
    $null = Connect-AzAccount -Identity -ErrorAction Stop
  }
  return (Get-AzContext)
}

function Set-SffProgress {
  # Write the SffProgress (+ optional SffStatus) resource-group tags that
  # scripts/monitor-sff.sh reads. Best-effort: a tagging failure never stops the build.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$Progress,
    [string]$Status,
    [hashtable]$Config
  )
  $progressKey = 'SffProgress'
  $statusKey = 'SffStatus'
  if ($Config -and $Config.Tags) {
    if ($Config.Tags.ProgressKey) { $progressKey = $Config.Tags.ProgressKey }
    if ($Config.Tags.StatusKey) { $statusKey = $Config.Tags.StatusKey }
  }
  try {
    Import-Module Az.Resources -ErrorAction Stop
    $rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
    $tags = $rg.Tags
    if ($null -eq $tags) { $tags = @{} }
    $tags[$progressKey] = $Progress
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $tags[$statusKey] = $Status }
    $null = Set-AzResourceGroup -ResourceGroupName $ResourceGroup -Tag $tags
    Write-SffLog "Progress tag set: $progressKey=$Progress$( if ($Status) { "  $statusKey=$Status" } )"
  }
  catch {
    Write-SffLog "Could not set progress tag ($Progress): $($_.Exception.Message)" -Level WARN
  }
}

function New-SffDirectories {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [hashtable]$Config)
  foreach ($p in $Config.Paths.GetEnumerator()) {
    if (-not (Test-Path $p.Value)) {
      New-Item -ItemType Directory -Force -Path $p.Value | Out-Null
    }
  }
}
