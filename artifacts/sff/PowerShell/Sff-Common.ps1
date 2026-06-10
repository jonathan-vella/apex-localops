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
  # Always pin the subscription: `Connect-AzAccount -Identity` alone can leave the context
  # with a null subscription, which then fails every management-plane call (e.g.
  # Get-AzResourceGroup -> "'this.Client.SubscriptionId' cannot be null").
  [CmdletBinding()]
  param(
    [string]$SubscriptionId = [Environment]::GetEnvironmentVariable('SFF_SubscriptionId', 'Machine'),
    [string]$TenantId = [Environment]::GetEnvironmentVariable('SFF_TenantId', 'Machine'),
    [int]$MaxAttempts = 12,
    [int]$DelaySeconds = 30
  )
  Import-Module Az.Accounts -ErrorAction Stop

  # Already connected with a usable subscription? Reuse it.
  try {
    $ctx = Get-AzContext
    if ($ctx -and $ctx.Subscription -and $ctx.Subscription.Id) {
      if (-not $SubscriptionId -or $ctx.Subscription.Id -eq $SubscriptionId) { return $ctx }
    }
  }
  catch { }

  # Connect with retry/backoff to ride out RBAC PROPAGATION LAG. The host runs Phase 2
  # almost immediately after its managed-identity role assignments are created, so the MI
  # token may not yet reflect them ("...recently granted, please refresh your credentials").
  #
  # Use a BARE `Connect-AzAccount -Identity` (NO -Subscription): the identity holds only
  # resource-group-scoped roles (least privilege), so the subscription LIST endpoint works
  # but a `-Subscription <id>` GET (which needs Microsoft.Resources/subscriptions/read at
  # subscription scope) would 403. After connecting, pin the subscription with Set-AzContext,
  # which switches context from the already-loaded profile (no extra subscription read).
  for ($i = 1; $i -le $MaxAttempts; $i++) {
    try {
      Write-SffLog "Connecting to Azure with the host managed identity (attempt $i/$MaxAttempts)..."
      $null = Connect-AzAccount -Identity -ErrorAction Stop -WarningAction SilentlyContinue
      $ctx = Get-AzContext
      if ($ctx -and $ctx.Subscription -and $ctx.Subscription.Id) {
        if ($SubscriptionId -and $ctx.Subscription.Id -ne $SubscriptionId) {
          try { $null = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop }
          catch { Write-SffLog "Set-AzContext to ${SubscriptionId} failed: $($_.Exception.Message)" -Level WARN }
          $ctx = Get-AzContext
        }
        if ($ctx -and $ctx.Subscription -and $ctx.Subscription.Id) {
          Write-SffLog "Connected. Subscription context: $($ctx.Subscription.Id)"
          return $ctx
        }
      }
      Write-SffLog "Connected but no subscription in context yet (RBAC propagating); retrying in ${DelaySeconds}s." -Level WARN
    }
    catch {
      Write-SffLog "Connect attempt $i/$MaxAttempts failed (likely RBAC propagation): $($_.Exception.Message)" -Level WARN
    }
    if ($i -lt $MaxAttempts) { Start-Sleep -Seconds $DelaySeconds }
  }

  Write-SffLog "Could not establish an Azure context after $MaxAttempts attempts." -Level ERROR
  return $null
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
    # Use the dedicated tags API (Update-AzTag -Operation Merge), NOT Set-AzResourceGroup.
    # Set-AzResourceGroup -Tag does a full resource-group PUT, which requires
    # Microsoft.Resources/subscriptions/resourceGroups/write - a permission the least-privilege
    # "Tag Contributor" role on the host identity does NOT grant (it would 403 with "does not
    # have authorization to perform action '.../resourcegroups/write'"). Update-AzTag maps to
    # Microsoft.Resources/tags/write, which Tag Contributor DOES grant, and Merge preserves any
    # existing tags (e.g. Project) while updating only the progress/status keys.
    $subId = $null
    try { $subId = (Get-AzContext).Subscription.Id } catch { $subId = $null }
    if (-not $subId) { $subId = [Environment]::GetEnvironmentVariable('SFF_SubscriptionId', 'Machine') }
    $rgId = "/subscriptions/$subId/resourceGroups/$ResourceGroup"
    $merge = @{ $progressKey = $Progress }
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $merge[$statusKey] = $Status }
    $null = Update-AzTag -ResourceId $rgId -Tag $merge -Operation Merge -ErrorAction Stop
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
    # Skip paths on a drive that does not exist yet (e.g. V: before the data disk is
    # initialized in Bootstrap-Sff.ps1). Those are created explicitly after disk init.
    $qualifier = Split-Path -Qualifier $p.Value -ErrorAction SilentlyContinue
    if ($qualifier -and -not (Test-Path "$qualifier\")) {
      continue
    }
    if (-not (Test-Path $p.Value)) {
      New-Item -ItemType Directory -Force -Path $p.Value | Out-Null
    }
  }
}
