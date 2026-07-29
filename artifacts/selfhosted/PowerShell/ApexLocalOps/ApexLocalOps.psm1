# =============================================================================
# apex-localops - ApexLocalOps.psm1
#
# Clean-room, ZERO-Jumpstart implementation of the nested Azure Local build. This
# module replaces the Azure.Arc.Jumpstart.* Gallery functions (New-DCVM,
# New-AzLocalNodeVM, Set-FabricNetwork, Invoke-AzureEdgeBootstrap, ...) with our
# own code that takes two operator-staged ISOs and produces a running, Arc-enabled
# 3-node Azure Local cluster.
#
# OWNED BUILD SCOPE (see docs/plans/plan-selfHostedAzureLocal.prompt.md): because
# this is a clean-room build, several areas that Jumpstart provided as a black box
# are implemented here from first principles and are the highest-risk parts. They
# are flagged inline with "OWNED-SCOPE:" so they are easy to find and harden:
#   • Convert-ApexIsoToVhdx       - ISO -> bootable Gen2 VHDX (no prebaked VHD).
#   • Connect-ApexNodeToArc       - Arc agent + the mandatory deploy extensions.
#   • New-ApexHostSwitch / nodes  - intent-based fabric networking.
#   • Set-ApexNodeTimeSync        - Azure Local is acutely time-sensitive.
#
# All VM guest operations use Hyper-V PowerShell Direct (Invoke-Command -VMId), so
# no guest network connectivity is required to configure the nested VMs.
# =============================================================================

$ErrorActionPreference = 'Stop'

#region ----------------------------------------------------------------- Common

function Get-ApexConfig {
  <#
  .SYNOPSIS Load the in-VM configuration (ApexLocal-Config.psd1).
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath = 'C:\ApexLocal\ApexLocal-Config.psd1'
  )
  if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
  return Import-PowerShellDataFile -Path $ConfigPath
}

function Write-ApexLog {
  <#
  .SYNOPSIS Consistent, timestamped logging to console + C:\ApexLocal\Logs.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO',
    [string]$LogDir = 'C:\ApexLocal\Logs',
    [string]$LogName = 'apexlocalops.log'
  )
  $line = "[{0}] [{1}] {2}" -f (Get-Date).ToString('u'), $Level, $Message
  Write-Host $line
  try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    Add-Content -Path (Join-Path $LogDir $LogName) -Value $line -ErrorAction SilentlyContinue
  }
  catch { }  # logging must never be fatal
}

function Connect-ApexAzure {
  <#
  .SYNOPSIS Authenticate with the host VM's system-assigned managed identity.
  .DESCRIPTION
    Bare Connect-AzAccount -Identity (NO -Subscription: the MI holds only
    resource-group-scoped roles), then pin the subscription with Set-AzContext.
    Retries with backoff to ride out RBAC propagation lag (the host runs almost
    immediately after its role assignments are created).
  #>
  [CmdletBinding()]
  param(
    [string]$SubscriptionId = [Environment]::GetEnvironmentVariable('APEX_SubscriptionId', 'Machine'),
    [int]$MaxAttempts = 12,
    [int]$DelaySeconds = 30
  )
  Import-Module Az.Accounts -ErrorAction Stop

  try {
    $ctx = Get-AzContext
    if ($ctx -and $ctx.Subscription -and $ctx.Subscription.Id) {
      if (-not $SubscriptionId -or $ctx.Subscription.Id -eq $SubscriptionId) { return $ctx }
    }
  }
  catch { }

  for ($i = 1; $i -le $MaxAttempts; $i++) {
    try {
      Write-ApexLog "Connecting to Azure with the host managed identity (attempt $i/$MaxAttempts)..."
      $null = Connect-AzAccount -Identity -ErrorAction Stop -WarningAction SilentlyContinue
      $ctx = Get-AzContext
      if ($ctx -and $ctx.Subscription -and $ctx.Subscription.Id) {
        if ($SubscriptionId -and $ctx.Subscription.Id -ne $SubscriptionId) {
          try { $null = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop }
          catch { Write-ApexLog "Set-AzContext to ${SubscriptionId} failed: $($_.Exception.Message)" -Level WARN }
          $ctx = Get-AzContext
        }
        if ($ctx -and $ctx.Subscription -and $ctx.Subscription.Id) {
          Write-ApexLog "Connected. Subscription context: $($ctx.Subscription.Id)"
          return $ctx
        }
      }
      Write-ApexLog "Connected but no subscription in context yet (RBAC propagating); retrying in ${DelaySeconds}s." -Level WARN
    }
    catch {
      Write-ApexLog "Connect attempt $i/$MaxAttempts failed (likely RBAC propagation): $($_.Exception.Message)" -Level WARN
    }
    if ($i -lt $MaxAttempts) { Start-Sleep -Seconds $DelaySeconds }
  }
  Write-ApexLog "Could not establish an Azure context after $MaxAttempts attempts." -Level ERROR
  return $null
}

function Set-ApexProgress {
  <#
  .SYNOPSIS Write the ApexProgress (+ optional ApexStatus) resource-group tags.
  .DESCRIPTION
    Uses Update-AzTag -Operation Merge (NOT Set-AzResourceGroup -Tag): the
    least-privilege Tag Contributor role grants Microsoft.Resources/tags/write but
    not resourcegroups/write. Best-effort: a tagging failure never stops the build.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$Progress,
    [string]$Status,
    [hashtable]$Config
  )
  $progressKey = 'ApexProgress'
  $statusKey = 'ApexStatus'
  if ($Config -and $Config.Tags) {
    if ($Config.Tags.ProgressKey) { $progressKey = $Config.Tags.ProgressKey }
    if ($Config.Tags.StatusKey) { $statusKey = $Config.Tags.StatusKey }
  }
  try {
    Import-Module Az.Resources -ErrorAction Stop
    $subId = $null
    try { $subId = (Get-AzContext).Subscription.Id } catch { $subId = $null }
    if (-not $subId) { $subId = [Environment]::GetEnvironmentVariable('APEX_SubscriptionId', 'Machine') }
    $rgId = "/subscriptions/$subId/resourceGroups/$ResourceGroup"
    $merge = @{ $progressKey = $Progress }
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) {
      $merge[$statusKey] = if ($Status.Length -gt 256) { $Status.Substring(0, 256) } else { $Status }
    }
    $null = Update-AzTag -ResourceId $rgId -Tag $merge -Operation Merge -ErrorAction Stop
    Write-ApexLog "Progress tag '$progressKey' = '$Progress'."
  }
  catch {
    Write-ApexLog "Could not set progress tag (continuing): $($_.Exception.Message)" -Level WARN
  }
}

function Send-ApexLogsToStorage {
  <#
  .SYNOPSIS Upload the in-VM build logs back to the storage 'logs' container (MI auth).
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$StorageAccountName,
    [string]$Container = 'logs',
    [string]$LogDir = 'C:\ApexLocal\Logs'
  )
  try {
    Import-Module Az.Storage -ErrorAction Stop
    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    $prefix = "$($env:COMPUTERNAME)/$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Get-ChildItem -Path $LogDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
      $relativePath = $_.FullName.Substring($LogDir.TrimEnd('\').Length).TrimStart('\') -replace '\\', '/'
      Set-AzStorageBlobContent -File $_.FullName -Container $Container `
        -Blob "$prefix/$relativePath" -Context $ctx -Force | Out-Null
    }
    Write-ApexLog "Uploaded build logs to $StorageAccountName/$Container/$prefix."
  }
  catch {
    Write-ApexLog "Log upload failed (continuing): $($_.Exception.Message)" -Level WARN
  }
}

function Clear-ApexBootstrapSecrets {
  <#
  .SYNOPSIS Remove transient lab credentials and unattended-build artifacts from the host.
  .DESCRIPTION
    The headless Hyper-V reboot requires a temporary Winlogon password and a
    machine-scoped base64 value. Remove both on every success or failure path,
    along with generated answer files that contain the same lab credential.
  #>
  [CmdletBinding()]
  param(
    [hashtable]$Config
  )

  $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  foreach ($propertyName in @('AutoAdminLogon', 'DefaultPassword', 'DefaultUserName', 'DefaultDomainName')) {
    Remove-ItemProperty -Path $winlogonPath -Name $propertyName -ErrorAction SilentlyContinue
  }

  [Environment]::SetEnvironmentVariable(
    'APEX_AdminPasswordB64',
    $null,
    [EnvironmentVariableTarget]::Machine
  )

  $answerDirectories = @('C:\ApexLocal')
  if ($Config -and $Config.Paths -and $Config.Paths.AnswerDir) {
    $answerDirectories += $Config.Paths.AnswerDir
  }
  foreach ($answerDirectory in $answerDirectories | Select-Object -Unique) {
    Get-ChildItem -Path $answerDirectory -Filter '*unattend*.xml' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
  }

  Write-ApexLog 'Cleared host bootstrap credentials and generated answer files.'
}

#endregion

#region ------------------------------------------------------------ Image pipeline

function Get-ApexIsoManifest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [object]$Context,
    [Parameter(Mandatory)] [string]$Container,
    [string]$ManifestBlob = 'iso-manifest.json',
    [string[]]$RequiredBlobs = @()
  )

  $manifestPath = Join-Path ([System.IO.Path]::GetTempPath()) ("apex-iso-manifest-{0}.json" -f [guid]::NewGuid())
  try {
    Get-AzStorageBlobContent -Container $Container -Blob $ManifestBlob -Destination $manifestPath `
      -Context $Context -Force -ErrorAction Stop | Out-Null
    try {
      $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
      throw "ISO manifest '$ManifestBlob' is not valid JSON: $($_.Exception.Message)"
    }
  }
  finally {
    Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
  }

  if ($manifest.schemaVersion -ne 1) {
    throw "ISO manifest '$ManifestBlob' has unsupported schemaVersion '$($manifest.schemaVersion)'."
  }

  $entries = @($manifest.files)
  if ($entries.Count -eq 0) {
    throw "ISO manifest '$ManifestBlob' contains no files."
  }

  $seenBlobs = @{}
  foreach ($entry in $entries) {
    if ([string]::IsNullOrWhiteSpace($entry.blob)) {
      throw "ISO manifest '$ManifestBlob' contains an entry without a blob name."
    }
    if ($seenBlobs.ContainsKey($entry.blob)) {
      throw "ISO manifest '$ManifestBlob' contains duplicate blob '$($entry.blob)'."
    }
    $seenBlobs[$entry.blob] = $true

    if ($null -eq $entry.bytes -or [long]$entry.bytes -le 0) {
      throw "ISO manifest entry '$($entry.blob)' has an invalid byte length."
    }
    if ($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
      throw "ISO manifest entry '$($entry.blob)' has an invalid SHA-256 digest."
    }

    $images = @($entry.images)
    if ($images.Count -eq 0) {
      throw "ISO manifest entry '$($entry.blob)' contains no image metadata."
    }
    foreach ($image in $images) {
      if ($null -eq $image.imageIndex -or [string]::IsNullOrWhiteSpace($image.imageName)) {
        throw "ISO manifest entry '$($entry.blob)' contains incomplete image metadata."
      }
    }
  }

  foreach ($requiredBlob in $RequiredBlobs) {
    if (-not $seenBlobs.ContainsKey($requiredBlob)) {
      throw "ISO manifest '$ManifestBlob' does not contain required blob '$requiredBlob'."
    }
  }

  return $manifest
}

function Wait-ApexStagedIso {
  <#
  .SYNOPSIS Block until BOTH ISOs are present in the storage container.
  .DESCRIPTION
    Mirrors the proven SFF "host waits for staged artifacts" pattern. Polls the
    iso-images container (MI auth) until both the Azure Local OS ISO and the
    Windows Server ISO exist, or the timeout elapses. Returns $true when both are
    present.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$StorageAccountName,
    [Parameter(Mandatory)] [string]$Container,
    [Parameter(Mandatory)] [string]$AzureLocalIsoBlob,
    [Parameter(Mandatory)] [string]$WindowsServerIsoBlob,
    [string]$ManifestBlob = 'iso-manifest.json',
    [int]$TimeoutMinutes = 720,
    [int]$PollSeconds = 60,
    [string]$ResourceGroup,
    [hashtable]$Config
  )
  Import-Module Az.Storage -ErrorAction Stop
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  $announced = $false
  while ((Get-Date) -lt $deadline) {
    try {
      $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
      $azl = Get-AzStorageBlob -Container $Container -Blob $AzureLocalIsoBlob -Context $ctx -ErrorAction SilentlyContinue
      $ws = Get-AzStorageBlob -Container $Container -Blob $WindowsServerIsoBlob -Context $ctx -ErrorAction SilentlyContinue
      $manifest = Get-AzStorageBlob -Container $Container -Blob $ManifestBlob -Context $ctx -ErrorAction SilentlyContinue
      if ($azl -and $ws -and $manifest) {
        Get-ApexIsoManifest -Context $ctx -Container $Container -ManifestBlob $ManifestBlob `
          -RequiredBlobs @($AzureLocalIsoBlob, $WindowsServerIsoBlob) | Out-Null
        Write-ApexLog "Both ISOs and a valid manifest are present: $AzureLocalIsoBlob ($([math]::Round($azl.Length/1GB,2)) GB), $WindowsServerIsoBlob ($([math]::Round($ws.Length/1GB,2)) GB)."
        return $true
      }
      $missing = @()
      if (-not $azl) { $missing += $AzureLocalIsoBlob }
      if (-not $ws) { $missing += $WindowsServerIsoBlob }
      if (-not $manifest) { $missing += $ManifestBlob }
      if (-not $announced -and $ResourceGroup) {
        Set-ApexProgress -ResourceGroup $ResourceGroup -Progress 'AwaitingIsos' -Status "Waiting for: $($missing -join ', ')" -Config $Config
        $announced = $true
      }
      Write-ApexLog "Waiting for ISO(s): $($missing -join ', '). Re-checking in ${PollSeconds}s."
    }
    catch {
      Write-ApexLog "ISO poll error (will retry): $($_.Exception.Message)" -Level WARN
    }
    Start-Sleep -Seconds $PollSeconds
  }
  throw "Timed out after $TimeoutMinutes min waiting for both ISOs and a valid manifest in $StorageAccountName/$Container."
}

function Get-ApexStagedIso {
  <#
  .SYNOPSIS Download one staged ISO from blob storage to a local path (MI auth).
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$StorageAccountName,
    [Parameter(Mandatory)] [string]$Container,
    [Parameter(Mandatory)] [string]$Blob,
    [Parameter(Mandatory)] [string]$Destination,
    [string]$ManifestBlob = 'iso-manifest.json'
  )
  Import-Module Az.Storage -ErrorAction Stop
  $dir = Split-Path -Parent $Destination
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

  $manifest = Get-ApexIsoManifest -Context $ctx -Container $Container -ManifestBlob $ManifestBlob -RequiredBlobs @($Blob)
  $manifestEntry = @($manifest.files | Where-Object { $_.blob -eq $Blob })[0]
  $expectedLength = [long]$manifestEntry.bytes
  $expectedHash = $manifestEntry.sha256.ToLowerInvariant()
  $remote = Get-AzStorageBlob -Container $Container -Blob $Blob -Context $ctx -ErrorAction Stop
  if ($remote.Length -ne $expectedLength) {
    throw "Staged blob size does not match the manifest for ${Blob}: blob=$($remote.Length) manifest=$expectedLength."
  }

  if (Test-Path -LiteralPath $Destination) {
    $localFile = Get-Item -LiteralPath $Destination
    $localHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($localFile.Length -eq $expectedLength -and $localHash -eq $expectedHash) {
      Write-ApexLog "ISO already present and matches manifest: $Destination (skipping download)."
      return $Destination
    }
    Remove-Item -LiteralPath $Destination -Force
  }

  $partialPath = "$Destination.partial"
  Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  try {
    Write-ApexLog "Downloading $Container/$Blob ($([math]::Round($expectedLength/1GB,2)) GB) -> $Destination"
    Get-AzStorageBlobContent -Container $Container -Blob $Blob -Destination $partialPath -Context $ctx -Force | Out-Null

    $downloadedLength = (Get-Item -LiteralPath $partialPath).Length
    if ($downloadedLength -ne $expectedLength) {
      throw "Downloaded size mismatch for ${Blob}: local=$downloadedLength manifest=$expectedLength."
    }
    $downloadedHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadedHash -ne $expectedHash) {
      throw "Downloaded SHA-256 mismatch for ${Blob}: local=$downloadedHash manifest=$expectedHash."
    }

    Move-Item -LiteralPath $partialPath -Destination $Destination -Force
  }
  finally {
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  }

  Write-ApexLog "Downloaded and verified against manifest: $Destination ($expectedLength bytes)."
  return $Destination
}

function Convert-ApexIsoToVhdx {
  <#
  .SYNOPSIS Convert a Windows/Azure Local ISO into a bootable Gen2 (UEFI) VHDX.
  .DESCRIPTION
    OWNED-SCOPE (highest risk): Jumpstart shipped a prebaked AzL-node.vhdx to avoid
    exactly this step. Here we build the VHDX ourselves with DISM:
      1. Mount the ISO and locate sources\install.wim (or install.esd).
      2. Create a dynamic VHDX and lay out a UEFI/GPT disk:
         EFI System Partition + MSR + Windows (OS) partition.
      3. Apply the chosen image index with DISM (Expand-WindowsImage).
      4. Make it bootable with bcdboot (UEFI firmware files on the ESP).
      5. Dismount everything and return the VHDX path.

    The resulting VHDX is Secure Boot / TPM capable (Gen2 UEFI layout), which the
    Azure Local security defaults (BitLocker / Credential Guard) require.

    The image is built at a temporary path, validated for its GPT partitions,
    Windows payload, and UEFI BCD store, then atomically promoted to the cache.
  #>
  [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
  param(
    [Parameter(Mandatory)] [string]$IsoPath,
    [Parameter(Mandatory)] [string]$VhdxPath,
    [int]$VhdxSizeGB = 127,
    [Parameter(Mandatory, ParameterSetName = 'ByName')] [string]$ImageName,
    [Parameter(Mandatory, ParameterSetName = 'ByIndex')] [ValidateRange(1, 65535)] [int]$ImageIndex
  )
  $dir = Split-Path -Parent $VhdxPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $partialPath = Join-Path $dir ("{0}.partial.vhdx" -f [System.IO.Path]::GetFileNameWithoutExtension($VhdxPath))

  function Get-AvailableDriveLetters {
    param([int]$Count)

    $usedLetters = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter |
      ForEach-Object { $_.DriveLetter.ToString().ToUpperInvariant() })
    $availableLetters = @(
      foreach ($codePoint in 90..68) {
        $candidate = [char]$codePoint
        if ($candidate -notin $usedLetters) { $candidate }
      }
    )
    if ($availableLetters.Count -lt $Count) {
      throw "Unable to reserve $Count drive letters for offline image conversion."
    }
    return @($availableLetters | Select-Object -First $Count)
  }

  function Test-BootableVhdx {
    param([Parameter(Mandatory)] [string]$Path)

    $assignedPartitions = @()
    try {
      $validationDisk = Mount-VHD -Path $Path -ReadOnly -Passthru -ErrorAction Stop | Get-Disk -ErrorAction Stop
      $partitions = @(Get-Partition -DiskNumber $validationDisk.Number -ErrorAction Stop)
      $efiPartition = $partitions | Where-Object GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' | Select-Object -First 1
      $osPartition = $partitions | Where-Object GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' | Select-Object -Last 1
      if (-not $efiPartition -or -not $osPartition) { return $false }

      $letters = @(Get-AvailableDriveLetters -Count 2)
      $efiPartition | Set-Partition -NewDriveLetter $letters[0] -ErrorAction Stop | Out-Null
      $assignedPartitions += [pscustomobject]@{ Partition = $efiPartition; AccessPath = "{0}:\" -f $letters[0] }
      $osPartition | Set-Partition -NewDriveLetter $letters[1] -ErrorAction Stop | Out-Null
      $assignedPartitions += [pscustomobject]@{ Partition = $osPartition; AccessPath = "{0}:\" -f $letters[1] }

      $windowsPath = "{0}:\Windows\System32" -f $letters[1]
      $bcdPath = "{0}:\EFI\Microsoft\Boot\BCD" -f $letters[0]
      return (Test-Path -LiteralPath $windowsPath) -and (Test-Path -LiteralPath $bcdPath)
    }
    catch {
      Write-ApexLog "VHDX validation failed for '$Path': $($_.Exception.Message)" -Level WARN
      return $false
    }
    finally {
      foreach ($assignment in $assignedPartitions) {
        Remove-PartitionAccessPath -DiskNumber $assignment.Partition.DiskNumber `
          -PartitionNumber $assignment.Partition.PartitionNumber -AccessPath $assignment.AccessPath `
          -ErrorAction SilentlyContinue
      }
      Dismount-VHD -Path $Path -ErrorAction SilentlyContinue
    }
  }

  if (Test-Path -LiteralPath $VhdxPath) {
    if (Test-BootableVhdx -Path $VhdxPath) {
      Write-ApexLog "Base VHDX already exists and passed boot validation: $VhdxPath"
      return $VhdxPath
    }
    Write-ApexLog "Removing invalid cached base VHDX: $VhdxPath" -Level WARN
    Remove-Item -LiteralPath $VhdxPath -Force
  }
  Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue

  Write-ApexLog "Mounting ISO: $IsoPath"
  $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
  try {
    $isoDrive = ($mount | Get-Volume -ErrorAction Stop).DriveLetter
    if (-not $isoDrive) { throw "Mounted ISO has no drive letter: $IsoPath" }
    $wim = Join-Path "$($isoDrive):" 'sources\install.wim'
    if (-not (Test-Path $wim)) { $wim = Join-Path "$($isoDrive):" 'sources\install.esd' }
    if (-not (Test-Path $wim)) { throw "No install.wim/esd found on the ISO (${isoDrive}:)." }

    $availableImages = @(Get-WindowsImage -ImagePath $wim -ErrorAction Stop)
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
      $matchingImages = @($availableImages | Where-Object { $_.ImageName -eq $ImageName })
      if ($matchingImages.Count -ne 1) {
        $available = ($availableImages | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" }) -join '; '
        throw "Image '$ImageName' not found in $wim. Available: $available"
      }
      $selectedImage = $matchingImages[0]
    }
    else {
      $matchingImages = @($availableImages | Where-Object { $_.ImageIndex -eq $ImageIndex })
      if ($matchingImages.Count -ne 1) {
        $available = ($availableImages | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" }) -join '; '
        throw "Image index '$ImageIndex' not found in $wim. Available: $available"
      }
      $selectedImage = $matchingImages[0]
    }
    $selectedIndex = $selectedImage.ImageIndex
    Write-ApexLog "Using image index $selectedIndex ('$($selectedImage.ImageName)') from $wim."

    Write-ApexLog "Creating VHDX: $partialPath (${VhdxSizeGB} GB dynamic)"
    New-VHD -Path $partialPath -SizeBytes ($VhdxSizeGB * 1GB) -Dynamic -ErrorAction Stop | Out-Null
    $disk = Mount-VHD -Path $partialPath -Passthru -ErrorAction Stop | Get-Disk -ErrorAction Stop
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false | Out-Null

    $driveLetters = @(Get-AvailableDriveLetters -Count 2)
    $efiDrive = $driveLetters[0]
    $osDrive = $driveLetters[1]
    $efi = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null
    $efi | Set-Partition -NewDriveLetter $efiDrive | Out-Null
    New-Partition -DiskNumber $disk.Number -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null
    $os = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
    Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'OS' -Confirm:$false | Out-Null
    $os | Set-Partition -NewDriveLetter $osDrive | Out-Null

    $applyPath = "${osDrive}:\"
    $efiPath = "${efiDrive}:"
    Write-ApexLog "Applying image index $selectedIndex to $applyPath (this takes several minutes)..."
    Expand-WindowsImage -ImagePath $wim -Index $selectedIndex -ApplyPath $applyPath -ErrorAction Stop | Out-Null
    Write-ApexLog "Writing UEFI boot files to $efiPath..."
    & "$env:SystemRoot\System32\bcdboot.exe" (Join-Path $applyPath 'Windows') /s $efiPath /f UEFI | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bcdboot failed with exit code $LASTEXITCODE." }

    Dismount-VHD -Path $partialPath -ErrorAction Stop
    if (-not (Test-BootableVhdx -Path $partialPath)) {
      throw "Converted VHDX failed boot validation: $partialPath"
    }
    Move-Item -LiteralPath $partialPath -Destination $VhdxPath -Force
    Write-ApexLog "Base VHDX ready and validated: $VhdxPath"
  }
  finally {
    Dismount-VHD -Path $partialPath -ErrorAction SilentlyContinue
    try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
  }
  return $VhdxPath
}

#endregion

#region -------------------------------------------------------------- Host fabric

function New-ApexHostSwitch {
  <#
  .SYNOPSIS Create the two internal Hyper-V switches + host WinNAT (Jumpstart model).
  .DESCRIPTION
    OWNED-SCOPE (fabric): mirrors Jumpstart LocalBox's New-InternalSwitch + Set-HostNAT.
    Creates TWO internal vSwitches:
      • SwitchName (mgmt/fabric, 192.168.1.0/24) — DC, router, nodes. The host takes
        HostInternalIp here but is NOT the gateway; the router VM (192.168.1.1) is.
      • NatSwitchName (NAT uplink, 192.168.128.0/24) — the host takes NatHostIp and
        runs a WinNAT (New-NetNat) that bridges nested egress onto the host's real
        Azure NIC. The router's second NIC lives here.
    Idempotent.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Network
  )
  # 1) Management/fabric internal switch (gateway is the router VM, not the host).
  if (-not (Get-VMSwitch -Name $Network.SwitchName -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Creating internal VM switch '$($Network.SwitchName)' (management/fabric)."
    New-VMSwitch -Name $Network.SwitchName -SwitchType Internal | Out-Null
  }
  $mgmtAlias = "vEthernet ($($Network.SwitchName))"
  if (-not (Get-NetIPAddress -InterfaceAlias $mgmtAlias -IPAddress $Network.HostInternalIp -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Assigning host management IP $($Network.HostInternalIp)/$($Network.PrefixLength) on '$mgmtAlias'."
    # No default gateway here: the host reaches the internet via its Azure NIC, and
    # the management subnet's gateway is the router VM.
    New-NetIPAddress -InterfaceAlias $mgmtAlias -IPAddress $Network.HostInternalIp -PrefixLength $Network.PrefixLength | Out-Null
  }

  # 2) NAT uplink switch + host WinNAT (bridges nested egress to the host Azure NIC).
  if (-not (Get-VMSwitch -Name $Network.NatSwitchName -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Creating internal VM switch '$($Network.NatSwitchName)' (NAT uplink)."
    New-VMSwitch -Name $Network.NatSwitchName -SwitchType Internal | Out-Null
  }
  $natAlias = "vEthernet ($($Network.NatSwitchName))"
  if (-not (Get-NetIPAddress -InterfaceAlias $natAlias -IPAddress $Network.NatHostIp -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Assigning host NAT-uplink IP $($Network.NatHostIp)/$($Network.PrefixLength) on '$natAlias'."
    New-NetIPAddress -InterfaceAlias $natAlias -IPAddress $Network.NatHostIp -PrefixLength $Network.PrefixLength | Out-Null
  }
  if (-not (Get-NetNat -Name $Network.NatSwitchName -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Creating host WinNAT '$($Network.NatSwitchName)' for $($Network.NatHostSubnet)."
    New-NetNat -Name $Network.NatSwitchName -InternalIPInterfaceAddressPrefix $Network.NatHostSubnet | Out-Null
  }
  Write-ApexLog "Host switches ready: $($Network.SwitchName) (mgmt) + $($Network.NatSwitchName) (NAT uplink)."
}

function New-ApexRouterVM {
  <#
  .SYNOPSIS Build the nested router VM — the management subnet's gateway (Jumpstart model).
  .DESCRIPTION
    OWNED-SCOPE (fabric): mirrors Jumpstart's New-RouterVM (vm-router / BGP-ToR-Router)
    adapted to this flat, single-level-nesting topology. A lightweight Windows Server
    VM built from the SAME base VHDX as the DC, with two NICs:
      • Mgmt (192.168.1.1) on the management switch — the gateway for DC + nodes.
      • NAT  (192.168.128.10) on the NAT-uplink switch — default route to the host.
    In-guest it enables IP forwarding, installs the Routing role (Install-RemoteAccess
    -VpnType RoutingOnly, matching Jumpstart) and a WinNAT that translates the
    management subnet out the NAT NIC. Net path:
      node -> router(192.168.1.1) -> router WinNAT -> 192.168.128.10
           -> host WinNAT(192.168.128.1) -> host Azure NIC -> internet.
    The two NICs are pinned to static MACs so the guest can tell them apart.
    Reuses New-ApexNestedVM for the disk/TPM/IMDS/unattend plumbing (DRY).
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [pscredential]$LocalAdminCredential,
    [Parameter(Mandatory)] [string]$WindowsServerBaseVhdx
  )
  $r = $Config.Router
  $net = $Config.Network
  $paths = $Config.Paths
  $mgmtMac = '0EAA00000101'
  $natMac = '0EAA00000102'

  $unattend = New-ApexUnattendXml -ComputerName $r.Name `
    -AdminPassword ($LocalAdminCredential.GetNetworkCredential().Password) `
    -OutputPath (Join-Path $paths.AnswerDir "$($r.Name)-unattend.xml")

  # Reuse the generic builder for the diff disk, TPM, IMDS-deny, unattend, and the
  # first (Mgmt) NIC on the management switch.
  New-ApexNestedVM -VmName $r.Name -BaseVhdxPath $WindowsServerBaseVhdx `
    -VmDiffDiskDir $paths.VmVhdDir -VmConfigDir $paths.VmDir -SwitchName $net.SwitchName `
    -MemoryMB $r.MemoryMB -CpuCount $r.CpuCount -UnattendPath $unattend `
    -ImdsAddress $net.ImdsAddress -EnableTpm | Out-Null

  # Pin the Mgmt NIC MAC (only one adapter exists yet), then add the NAT-uplink NIC.
  Set-VMNetworkAdapter -VMName $r.Name -StaticMacAddress $mgmtMac
  Add-VMNetworkAdapter -VMName $r.Name -Name 'NAT' -SwitchName $net.NatSwitchName -StaticMacAddress $natMac
  $natAdapter = Get-VMNetworkAdapter -VMName $r.Name -Name 'NAT'
  Add-VMNetworkAdapterAcl -VMNetworkAdapter $natAdapter -Action Deny -Direction Inbound  -RemoteIPAddress $net.ImdsAddress
  Add-VMNetworkAdapterAcl -VMNetworkAdapter $natAdapter -Action Deny -Direction Outbound -RemoteIPAddress $net.ImdsAddress

  Start-VM -Name $r.Name
  Wait-ApexVMReady -VmName $r.Name -Credential $LocalAdminCredential | Out-Null

  Write-ApexLog "Configuring router '$($r.Name)' (gateway $($r.MgmtIp), NAT uplink $($r.NatIp))."
  Invoke-Command -VMName $r.Name -Credential $LocalAdminCredential -ScriptBlock {
    param($mgmtMac, $natMac, $mgmtIp, $mgmtPfx, $dns, $natIp, $natPfx, $natGw, $mgmtSubnet)
    $mgmtNic = Get-NetAdapter | Where-Object { ($_.MacAddress -replace '[:-]', '') -eq $mgmtMac }
    $natNic = Get-NetAdapter | Where-Object { ($_.MacAddress -replace '[:-]', '') -eq $natMac }
    # Mgmt NIC: gateway IP for the management subnet, DNS = DC, NO default gateway.
    New-NetIPAddress -InterfaceIndex $mgmtNic.ifIndex -IPAddress $mgmtIp -PrefixLength $mgmtPfx -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $mgmtNic.ifIndex -ServerAddresses $dns
    # NAT uplink NIC: address on the host NAT subnet + default route via the host.
    New-NetIPAddress -InterfaceIndex $natNic.ifIndex -IPAddress $natIp -PrefixLength $natPfx -DefaultGateway $natGw -ErrorAction SilentlyContinue | Out-Null
    # Enable IP forwarding on both interfaces.
    Set-NetIPInterface -InterfaceIndex $mgmtNic.ifIndex -Forwarding Enabled
    Set-NetIPInterface -InterfaceIndex $natNic.ifIndex -Forwarding Enabled
    # Routing role (Jumpstart parity) + WinNAT to translate the mgmt subnet out the
    # NAT NIC. RoutingOnly does not itself NAT, so WinNAT is the single translator
    # here (no RRAS/WinNAT conflict).
    Install-WindowsFeature -Name Routing, RSAT-RemoteAccess-PowerShell -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Import-Module RemoteAccess -ErrorAction SilentlyContinue
    try { Install-RemoteAccess -VpnType RoutingOnly -ErrorAction SilentlyContinue } catch { }
    Get-NetNat -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue
    New-NetNat -Name 'ApexRouterNAT' -InternalIPInterfaceAddressPrefix $mgmtSubnet -ErrorAction SilentlyContinue | Out-Null

    $nat = Get-NetNat -Name 'ApexRouterNAT' -ErrorAction Stop
    $defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
    Where-Object NextHop -eq $natGw | Select-Object -First 1
    $forwardingInterfaces = @(Get-NetIPInterface -AddressFamily IPv4 |
      Where-Object { $_.InterfaceIndex -in @($mgmtNic.ifIndex, $natNic.ifIndex) -and $_.Forwarding -eq 'Enabled' })
    if (-not $nat -or -not $defaultRoute -or $forwardingInterfaces.Count -ne 2) {
      throw 'Router forwarding, NAT, or default-route verification failed.'
    }
    # Azure Local's infra IP readiness check assigns each pool address to a temporary
    # test adapter and pings the gateway. Routing alone is not enough: Windows blocks
    # inbound ICMP echo by default, so the gateway routes traffic fine while appearing
    # dead to that check. Answering echo is a hard requirement for deployment.
    New-NetFirewallRule -Name 'ApexLocal-ICMP4-Echo-In' -DisplayName 'ApexLocal ICMPv4 Echo Request (In)' `
      -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow -Profile Any `
      -ErrorAction SilentlyContinue | Out-Null
    Enable-NetFirewallRule -Name 'ApexLocal-ICMP4-Echo-In' -ErrorAction SilentlyContinue
    $echoRule = Get-NetFirewallRule -Name 'ApexLocal-ICMP4-Echo-In' -ErrorAction SilentlyContinue
    if (-not $echoRule -or $echoRule.Enabled -ne 'True') {
      throw 'Router ICMPv4 echo firewall rule is missing or disabled; the Azure Local infra IP readiness check will fail.'
    }
  } -ArgumentList $mgmtMac, $natMac, $r.MgmtIp, $net.PrefixLength, $net.DnsServers[0], $r.NatIp, $net.PrefixLength, $net.NatHostIp, $net.SubnetPrefix

  Write-ApexLog "Router '$($r.Name)' ready (management gateway $($r.MgmtIp))."
}

#endregion

#region ------------------------------------------------------------ Nested build

function New-ApexUnattendXml {
  <#
  .SYNOPSIS Build an offline unattend.xml for a nested VM (computer name + admin + locale).
  .DESCRIPTION
    Networking is deliberately NOT set here: static IPs are applied post-boot via
    PowerShell Direct (more reliable than offline NIC config). The file is injected
    into the OS partition's Panther folder by New-ApexNestedVM.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$ComputerName,
    [Parameter(Mandatory)] [string]$AdminPassword,
    [string]$OutputPath,
    [string]$Locale = 'en-US',
    [string]$TimeZone = 'UTC'
  )
  [xml]$xml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName />
      <TimeZone />
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale />
      <SystemLocale />
      <UILanguage />
      <UserLocale />
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <UserAccounts>
        <AdministratorPassword>
          <Value />
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
        <NetworkLocation>Work</NetworkLocation>
      </OOBE>
    </component>
  </settings>
</unattend>
'@
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $namespaceManager.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
  $specialize = $xml.SelectSingleNode("//u:settings[@pass='specialize']/u:component", $namespaceManager)
  $specialize.SelectSingleNode('u:ComputerName', $namespaceManager).InnerText = $ComputerName
  $specialize.SelectSingleNode('u:TimeZone', $namespaceManager).InnerText = $TimeZone

  $international = $xml.SelectSingleNode(
    "//u:settings[@pass='oobeSystem']/u:component[@name='Microsoft-Windows-International-Core']",
    $namespaceManager
  )
  foreach ($elementName in @('InputLocale', 'SystemLocale', 'UILanguage', 'UserLocale')) {
    $international.SelectSingleNode("u:$elementName", $namespaceManager).InnerText = $Locale
  }
  $passwordNode = $xml.SelectSingleNode('//u:AdministratorPassword/u:Value', $namespaceManager)
  $passwordNode.InnerText = $AdminPassword

  if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writerSettings.Indent = $true
    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $writerSettings)
    try { $xml.Save($writer) }
    finally { $writer.Dispose() }
    return $OutputPath
  }
  return $xml.OuterXml
}

function Add-ApexImdsDenyAcl {
  <#
  .SYNOPSIS Apply the IMDS deny port ACLs to a nested adapter without duplicating them.
  .DESCRIPTION
    Hyper-V rejects an identical port ACL with 0x800700B7 ('Cannot create a file when
    that file already exists'). A node receives its fabric adapter from New-ApexNestedVM,
    which already denies IMDS, and then adds storage adapters that must be denied too,
    so the invariant 'every adapter denies IMDS' has to be applied idempotently.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [object]$VMNetworkAdapter,
    [Parameter(Mandatory)] [string]$RemoteIPAddress
  )

  $existing = @(Get-VMNetworkAdapterAcl -VMNetworkAdapter $VMNetworkAdapter -ErrorAction SilentlyContinue)
  foreach ($direction in @('Inbound', 'Outbound')) {
    $alreadyApplied = @($existing | Where-Object {
        $_.Direction -eq $direction -and $_.Action -eq 'Deny' -and
        [string]$_.RemoteAddress -eq $RemoteIPAddress
      })
    if ($alreadyApplied.Count -eq 0) {
      Add-VMNetworkAdapterAcl -VMNetworkAdapter $VMNetworkAdapter -Action Deny `
        -Direction $direction -RemoteIPAddress $RemoteIPAddress
    }
  }
}

function New-ApexNestedVM {
  <#
  .SYNOPSIS Create a Generation 2 nested VM from a base VHDX (differencing disk).
  .DESCRIPTION
    Creates a Gen2 VM with a differencing disk off the converted base VHDX, static
    memory, the requested vCPU count, Windows Secure Boot, a TPM (key protector +
    Enable-VMTPM), and an IMDS deny ACL on the
    nested adapter (OWNED-SCOPE M4: stops a nested node from grabbing the Azure
    HOST's managed identity at 169.254.169.254). Optionally injects an unattend.xml.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [string]$BaseVhdxPath,
    [Parameter(Mandatory)] [string]$VmDiffDiskDir,
    [Parameter(Mandatory)] [string]$VmConfigDir,
    [Parameter(Mandatory)] [string]$SwitchName,
    [int]$MemoryMB = 4096,
    [int]$CpuCount = 4,
    [string]$UnattendPath,
    [string]$ImdsAddress = '169.254.169.254',
    [switch]$EnableTpm
  )
  # Idempotency: remove any prior instance + its differencing disk.
  $existing = Get-VM -Name $VmName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-ApexLog "Removing existing VM '$VmName' for a clean rebuild." -Level WARN
    if ($existing.State -ne 'Off') { Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue }
    Remove-VM -Name $VmName -Force -ErrorAction SilentlyContinue

    # Rebuilding the VM does not remove its Azure-side Arc machine. Left behind, the
    # Arc pre-registration check fails with "Arc machine(s) ... already exists in the
    # Resource Group", which reads like a configuration fault rather than stale state.
    $subscriptionId = [Environment]::GetEnvironmentVariable('APEX_SubscriptionId', 'Machine')
    $resourceGroup = [Environment]::GetEnvironmentVariable('APEX_ResourceGroup', 'Machine')
    if ($subscriptionId -and $resourceGroup) {
      $arcPath = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup" +
      "/providers/Microsoft.HybridCompute/machines/$VmName"
      try {
        $existingArc = Invoke-AzRestMethod -Method GET -Path "${arcPath}?api-version=2024-07-10" `
          -ErrorAction Stop
        if ($existingArc.StatusCode -eq 200) {
          $null = Invoke-AzRestMethod -Method DELETE -Path "${arcPath}?api-version=2024-07-10" `
            -ErrorAction Stop
          Write-ApexLog "Removed stale Arc machine '$VmName' left by the previous build."
        }
      }
      catch {
        Write-ApexLog "Could not clean the Arc machine for '$VmName': $($_.Exception.Message)" -Level WARN
      }
    }
  }
  if (-not (Test-Path $VmDiffDiskDir)) { New-Item -ItemType Directory -Force -Path $VmDiffDiskDir | Out-Null }
  $diff = Join-Path $VmDiffDiskDir "$VmName.vhdx"
  if (Test-Path $diff) { Remove-Item $diff -Force -ErrorAction SilentlyContinue }

  Write-ApexLog "Creating differencing disk for '$VmName' off base: $BaseVhdxPath"
  New-VHD -Path $diff -ParentPath $BaseVhdxPath -Differencing | Out-Null
  if ($UnattendPath) {
    # Inject the unattend into the OS partition (Panther) of the differencing disk.
    $m = Mount-VHD -Path $diff -Passthru | Get-Disk
    $temporaryAccessPath = $null
    $osPartition = $null
    try {
      $osPartition = Get-Partition -DiskNumber $m.Number |
      Where-Object GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' |
      Sort-Object Size -Descending | Select-Object -First 1
      $osVolume = $osPartition | Get-Volume
      if (-not $osPartition -or $osVolume.FileSystem -ne 'NTFS') {
        throw "Could not find the NTFS OS partition in '$diff'."
      }

      $driveLetter = $osVolume.DriveLetter
      if (-not $driveLetter) {
        $usedLetters = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter |
          ForEach-Object { $_.DriveLetter.ToString().ToUpperInvariant() })
        $driveLetter = @(68..90 | ForEach-Object { [char]$_ }) |
        Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
        if (-not $driveLetter) { throw 'No drive letter is available for unattend injection.' }
        $temporaryAccessPath = "${driveLetter}:\"
        $osPartition | Set-Partition -NewDriveLetter $driveLetter -ErrorAction Stop | Out-Null
      }

      $panther = "${driveLetter}:\Windows\Panther"
      New-Item -ItemType Directory -Force -Path $panther | Out-Null
      $destination = Join-Path $panther 'unattend.xml'
      Copy-Item -LiteralPath $UnattendPath -Destination $destination -Force
      if (-not (Test-Path -LiteralPath $destination)) {
        throw "Unattend injection verification failed for '$VmName'."
      }
      Write-ApexLog "Injected unattend.xml into '$VmName' (${driveLetter}:)."
    }
    finally {
      if ($temporaryAccessPath -and $osPartition) {
        Remove-PartitionAccessPath -DiskNumber $osPartition.DiskNumber `
          -PartitionNumber $osPartition.PartitionNumber -AccessPath $temporaryAccessPath `
          -ErrorAction SilentlyContinue
      }
      Dismount-VHD -Path $diff -ErrorAction SilentlyContinue
    }
  }

  # VM configuration must live on the pooled V: volume. Hyper-V writes a .VMRS
  # memory-contents file the size of the VM's RAM next to the configuration, and a
  # 96-GB node cannot allocate that on the small OS disk.
  if (-not (Test-Path $VmConfigDir)) { New-Item -ItemType Directory -Force -Path $VmConfigDir | Out-Null }
  New-VM -Name $VmName -Generation 2 -MemoryStartupBytes ($MemoryMB * 1MB) `
    -VHDPath $diff -SwitchName $SwitchName -Path $VmConfigDir | Out-Null
  Set-VM -Name $VmName -SmartPagingFilePath $VmConfigDir -SnapshotFileLocation $VmConfigDir
  Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false
  Set-VMProcessor -VMName $VmName -Count $CpuCount -ExposeVirtualizationExtensions $true

  if ($EnableTpm) {
    # All nested guests in this profile are Windows; the generic UEFI CA template
    # does not trust the Windows boot manager used by these offline-applied images.
    Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows'
    Set-VMKeyProtector -VMName $VmName -NewLocalKeyProtector
    Enable-VMTPM -VMName $VmName
  }

  Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue

  # OWNED-SCOPE M4: deny the Azure-VM IMDS endpoint on the nested adapter BEFORE boot.
  $adapter = (Get-VMNetworkAdapter -VMName $VmName)[0]
  Add-ApexImdsDenyAcl -VMNetworkAdapter $adapter -RemoteIPAddress $ImdsAddress

  Write-ApexLog "Nested VM '$VmName' created (Gen2, ${MemoryMB}MB, ${CpuCount} vCPU, TPM=$($EnableTpm.IsPresent))."
  return $VmName
}

function Wait-ApexVMReady {
  <#
  .SYNOPSIS Wait until PowerShell Direct works inside the VM with the given credential.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [pscredential]$Credential,
    [int]$TimeoutMinutes = 30
  )
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  while ((Get-Date) -lt $deadline) {
    try {
      $ok = Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
      if ($ok) { Write-ApexLog "PowerShell Direct is up on '$VmName' ($ok)."; return $true }
    }
    catch { }
    Start-Sleep -Seconds 20
  }
  throw "Timed out waiting for PowerShell Direct on '$VmName'."
}

function New-ApexDomainController {
  <#
  .SYNOPSIS Build the nested domain controller (AD DS forest + DNS + NTP authority).
  .DESCRIPTION
    Creates a Gen2 VM from the Windows Server base VHDX, applies a static IP via
    PowerShell Direct, promotes it to a new forest, and configures it as the
    authoritative time source (OWNED-SCOPE M5: Azure Local is acutely time-sensitive).
    Initialize-ApexActiveDirectory subsequently runs Microsoft's supported AD
    precreation tool to create the deployment OU, LCM account, groups, and gMSAs.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [pscredential]$LocalAdminCredential,
    [Parameter(Mandatory)] [securestring]$SafeModePassword,
    [Parameter(Mandatory)] [string]$WindowsServerBaseVhdx
  )
  $dom = $Config.Domain
  $net = $Config.Network
  $paths = $Config.Paths

  $unattend = New-ApexUnattendXml -ComputerName $dom.DcHostName `
    -AdminPassword ($LocalAdminCredential.GetNetworkCredential().Password) `
    -OutputPath (Join-Path $paths.AnswerDir "$($dom.DcHostName)-unattend.xml")

  New-ApexNestedVM -VmName $dom.DcHostName -BaseVhdxPath $WindowsServerBaseVhdx `
    -VmDiffDiskDir $paths.VmVhdDir -VmConfigDir $paths.VmDir -SwitchName $net.SwitchName `
    -MemoryMB 4096 -CpuCount 4 -UnattendPath $unattend -ImdsAddress $net.ImdsAddress -EnableTpm | Out-Null

  Start-VM -Name $dom.DcHostName
  Wait-ApexVMReady -VmName $dom.DcHostName -Credential $LocalAdminCredential | Out-Null

  # Static IP + loopback DNS via PowerShell Direct.
  Write-ApexLog "Configuring DC static IP $($dom.DcIpAddress)/$($net.PrefixLength)."
  $null = Invoke-Command -VMName $dom.DcHostName -Credential $LocalAdminCredential -ScriptBlock {
    param($ip, $prefix, $gw)
    $if = (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1)
    New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $if.ifIndex -ServerAddresses '127.0.0.1'
  } -ArgumentList $dom.DcIpAddress, $net.PrefixLength, $net.Gateway

  # Promote to a new forest.
  Write-ApexLog "Promoting '$($dom.DcHostName)' to forest '$($dom.Fqdn)' (a reboot follows)."
  $null = Invoke-Command -VMName $dom.DcHostName -Credential $LocalAdminCredential -ScriptBlock {
    param($fqdn, $netbios, $safePwd)
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    Import-Module ADDSDeployment
    Install-ADDSForest -DomainName $fqdn -DomainNetbiosName $netbios `
      -SafeModeAdministratorPassword $safePwd -InstallDns -Force -NoRebootOnCompletion:$false
  } -ArgumentList $dom.Fqdn, $dom.NetBiosName, $SafeModePassword

  # Wait for the DC to come back as a domain controller.
  $domainCred = New-Object System.Management.Automation.PSCredential(
    "$($dom.NetBiosName)\Administrator", $LocalAdminCredential.Password)
  Start-Sleep -Seconds 60
  Wait-ApexVMReady -VmName $dom.DcHostName -Credential $domainCred -TimeoutMinutes 30 | Out-Null

  # Configure authoritative time (M5). The supported Microsoft AD preparation
  # tool owns OU and deployment-account creation in the next orchestration stage.
  # The integration service must be off first: while it is enabled the VM IC provider
  # outranks the configured peer, the DC never becomes a reliable source, and every node
  # then fails AzStackHci_Software_NtpServer-Sync even though it can reach the DC.
  Disable-VMIntegrationService -VMName $dom.DcHostName -Name 'Time Synchronization' `
    -ErrorAction SilentlyContinue
  $healthDeadline = (Get-Date).AddMinutes(15)
  $healthError = $null
  while ((Get-Date) -lt $healthDeadline) {
    try {
      $null = Invoke-Command -VMName $dom.DcHostName -Credential $domainCred -ErrorAction Stop -ScriptBlock {
        param($fqdn)
        # Authoritative NTP from the PDC emulator; do not sync from the (paused) host clock.
        w32tm /config /manualpeerlist:"time.windows.com,0x9" /syncfromflags:manual /reliable:yes /update | Out-Null
        Restart-Service w32time -ErrorAction SilentlyContinue
        w32tm /resync /force | Out-Null
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain -Identity $fqdn -ErrorAction Stop
        $dnsRecord = Resolve-DnsName -Name $fqdn -Server '127.0.0.1' -ErrorAction Stop
        $requiredServices = Get-Service -Name ADWS, DNS, NTDS -ErrorAction Stop
        if ($domain.DNSRoot -ne $fqdn -or -not $dnsRecord -or
          @($requiredServices | Where-Object Status -ne 'Running').Count -gt 0) {
          throw "Domain controller health verification failed for '$fqdn'."
        }
        w32tm /query /status | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Domain controller time-service verification failed for '$fqdn'." }
        # A DC still on the VM IC provider is not a usable upstream for the nodes.
        $dcSource = (w32tm /query /source).Trim()
        if ($dcSource -in @('Local CMOS Clock', 'VM IC Time Synchronization Provider')) {
          throw "Domain controller is not an authoritative time source (source '$dcSource')."
        }
      } -ArgumentList $dom.Fqdn
      $healthError = $null
      break
    }
    catch {
      $healthError = $_.Exception.Message
      Write-ApexLog "Domain controller services are not ready; retrying in 20s: $healthError" -Level WARN
      Start-Sleep -Seconds 20
    }
  }
  if ($healthError) {
    throw "Timed out waiting for domain controller health. Last error: $healthError"
  }

  Write-ApexLog "Domain controller '$($dom.DcHostName)' ready (forest $($dom.Fqdn))."
  return $domainCred
}

function Test-ApexCommandContract {
  <#
  .SYNOPSIS Verify every external command and parameter this build depends on exists.
  .DESCRIPTION
    Several release defects were plausible-looking commands or parameters that simply
    do not exist: a fabricated vTPM getter, a wrong checkpoint-location parameter, a
    missing VM configuration path, and a wrong network-validation credential name.
    Parsing, linting and source-text contracts cannot detect any of them, and each
    surfaced only after the build had already run for many minutes. Checking the real
    command metadata costs seconds and fails before the first nested VM is created.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Contract
  )

  $failures = @()
  foreach ($commandName in ($Contract.Keys | Sort-Object)) {
    # Get-Command triggers module auto-loading, so pinned modules installed during
    # bootstrap are discovered without importing them here.
    $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
    if (-not $command) {
      $failures += "missing command '$commandName'"
      continue
    }
    foreach ($parameterName in $Contract[$commandName]) {
      if (-not $command.Parameters.ContainsKey($parameterName)) {
        $failures += "'$commandName' has no parameter '-$parameterName'"
      }
    }
  }

  if ($failures.Count -gt 0) {
    throw "Command contract check failed: $($failures -join '; ')."
  }
  Write-ApexLog "Command contract verified for $($Contract.Count) command(s)."
}

function Install-ApexGuestModule {
  <#
  .SYNOPSIS Side-load a pinned PowerShell module from the outer host into a nested guest.
  .DESCRIPTION
    Nested guests are freshly applied offline Windows images: PSGallery is not a
    registered repository, the NuGet provider is absent, and their only egress path
    runs through the lab's own nested router. Acquiring modules inside a guest is
    therefore fragile and has failed in practice. The outer host already has proven
    egress and installs its pinned modules during bootstrap, so this resolves the
    module once on the host and copies it into the guest over an existing PowerShell
    Direct session.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'Each remote scriptblock declares its own param() block and receives values through -ArgumentList; $using: does not apply to that pattern.'
  )]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$RequiredVersion,
    [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession]$Session,
    [Parameter(Mandatory)] [string]$StagingPath
  )

  $versionPath = Join-Path (Join-Path $StagingPath $Name) $RequiredVersion
  $manifestPath = Join-Path $versionPath "$Name.psd1"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    if (-not (Test-Path -LiteralPath $StagingPath)) {
      New-Item -ItemType Directory -Force -Path $StagingPath | Out-Null
    }
    # A host image that never ran Register-PSRepository has no PSGallery either.
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
      Register-PSRepository -Default -ErrorAction Stop
    }
    Write-ApexLog "Downloading '$Name' $RequiredVersion on the host for guest side-load."
    Save-Module -Name $Name -RequiredVersion $RequiredVersion -Path $StagingPath `
      -Repository PSGallery -Force -ErrorAction Stop
  }
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Host staging for '$Name' $RequiredVersion produced no manifest at '$manifestPath'."
  }

  $guestModuleRoot = Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
    param([string]$moduleName)
    $root = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\$moduleName"
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $root
  } -ArgumentList $Name

  Copy-Item -Path $versionPath -Destination $guestModuleRoot -ToSession $Session `
    -Recurse -Force -ErrorAction Stop

  $importedVersion = Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
    param([string]$moduleName, [string]$moduleVersion)
    $null = Import-Module -Name $moduleName -RequiredVersion $moduleVersion -Force -ErrorAction Stop
    (Get-Module -Name $moduleName | Select-Object -First 1).Version.ToString()
  } -ArgumentList $Name, $RequiredVersion

  if ($importedVersion -ne $RequiredVersion) {
    throw "Guest import of '$Name' resolved version '$importedVersion' instead of '$RequiredVersion'."
  }
  Write-ApexLog "Side-loaded '$Name' $RequiredVersion into the guest; no gallery access was required."
}

function Initialize-ApexActiveDirectory {
  <#
  .SYNOPSIS Prepare the Azure Local OU and dedicated LCM deployment account.
  .DESCRIPTION
    Runs Microsoft's pinned AsHciADArtifactsPreCreationTool on the nested domain
    controller. The tool is acquired on the outer host and side-loaded into the
    guest because a freshly promoted DC has no registered PSGallery. The LCM
    account is distinct from the local administrator, while this evaluation
    profile intentionally reuses the approved lab password.
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces',
    '',
    Justification = 'The remote scriptblock declares its own param() block and receives values through -ArgumentList; $using: does not apply to that pattern.'
  )]
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [pscredential]$DomainAdminCredential,
    [Parameter(Mandatory)] [securestring]$LcmPassword
  )

  $dom = $Config.Domain
  $versionsPath = Join-Path $Config.Paths.RootDir 'ModuleVersions.psd1'
  $moduleVersions = Import-PowerShellDataFile -Path $versionsPath
  $toolVersion = $moduleVersions.AsHciADArtifactsPreCreationTool

  Write-ApexLog "Preparing Azure Local AD objects in '$($dom.OuPath)' with Microsoft's supported tool."
  $session = New-PSSession -VMName $dom.DcHostName -Credential $DomainAdminCredential -ErrorAction Stop
  try {
    Install-ApexGuestModule -Name 'AsHciADArtifactsPreCreationTool' -RequiredVersion $toolVersion `
      -Session $session -StagingPath (Join-Path $Config.Paths.RootDir 'GuestModules')

    # Suppress the remote success stream: this function must return only the LCM credential.
    $null = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
      param(
        [string]$moduleVersion,
        [string]$lcmUserName,
        [securestring]$lcmPassword,
        [string]$ouPath
      )

      Import-Module AsHciADArtifactsPreCreationTool -RequiredVersion $moduleVersion -Force

      $lcmCredential = New-Object System.Management.Automation.PSCredential($lcmUserName, $lcmPassword)
      $null = New-HciAdObjectsPreCreation -AzureStackLCMUserCredential $lcmCredential -AsHciOUName $ouPath

      Import-Module ActiveDirectory
      Import-Module GroupPolicy
      $null = Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop
      $null = Get-ADUser -Identity $lcmUserName -ErrorAction Stop
      $inheritance = Get-GPInheritance -Target $ouPath
      if (-not $inheritance.GpoInheritanceBlocked) {
        throw "Group Policy inheritance is not blocked on '$ouPath'."
      }
    } -ArgumentList $toolVersion, $dom.LcmUserName, $LcmPassword, $dom.OuPath
  }
  finally {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
  }

  Write-ApexLog "Azure Local AD preparation completed for LCM user '$($dom.LcmUserName)'."
  return New-Object System.Management.Automation.PSCredential(
    "$($dom.NetBiosName)\$($dom.LcmUserName)",
    $LcmPassword
  )
}

function Set-ApexNodeTimeSync {
  <#
  .SYNOPSIS Point a node's clock at the nested DC (OWNED-SCOPE M5) and disable host sync.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [pscredential]$Credential,
    [Parameter(Mandatory)] [string]$DcIpAddress
  )
  # Disable the Hyper-V Time Synchronization integration service so the paused host
  # clock cannot drag the node's time; sync from the DC instead.
  Disable-VMIntegrationService -VMName $VmName -Name 'Time Synchronization' -ErrorAction SilentlyContinue
  Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock {
    param($dc)
    w32tm /config /manualpeerlist:"$dc,0x9" /syncfromflags:manual /update | Out-Null
    Restart-Service w32time -ErrorAction SilentlyContinue

    # Setting the source is not the same as being in sync. A freshly built node needs a
    # few resync attempts before the service reports a successful sync, and the Software
    # validator fails AzStackHci_Software_NtpServer-Sync until it does.
    $deadline = (Get-Date).AddMinutes(10)
    $source = ''
    $synced = $false
    do {
      w32tm /resync /force | Out-Null
      Start-Sleep -Seconds 15
      $status = (w32tm /query /status 2>&1) -join "`n"
      $source = (w32tm /query /source 2>&1).Trim()
      $sourceValid = $source -notin @('Local CMOS Clock', 'VM IC Time Synchronization Provider')
      $everSynced = ($status -match 'Last Successful Sync Time:') -and
      ($status -notmatch 'Last Successful Sync Time:\s*unspecified')
      $synced = $sourceValid -and $everSynced
    } while (-not $synced -and (Get-Date) -lt $deadline)

    if (-not $synced) {
      throw "Node did not synchronize time with DC '$dc' within 10 minutes (source '$source')."
    }
  } -ArgumentList $DcIpAddress
  $timeIntegration = Get-VMIntegrationService -VMName $VmName -Name 'Time Synchronization' -ErrorAction Stop
  if ($timeIntegration.Enabled) { throw "Hyper-V time synchronization is still enabled for '$VmName'." }
  Write-ApexLog "Node '$VmName' time source set to DC $DcIpAddress."
}

function New-ApexLocalNode {
  <#
  .SYNOPSIS Build one nested Azure Local node from the Azure Local base VHDX.
  .DESCRIPTION
    Creates a Gen2 node VM (TPM on, Secure Boot on), applies a static management IP
    via PowerShell Direct, sets DNS to the DC, and (OWNED-SCOPE M1) attaches the
    additional storage-intent adapters. Returns the node's IP for the cluster params.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [int]$Index,
    [Parameter(Mandatory)] [pscredential]$LocalAdminCredential,
    [Parameter(Mandatory)] [string]$AzureLocalBaseVhdx
  )
  $c = $Config.Cluster
  $net = $Config.Network
  $paths = $Config.Paths

  $name = "$($c.NamePrefix)$Index"
  # Node IP = NodeStartIp with the last octet incremented by (Index-1).
  $startParts = $c.NodeStartIp.Split('.')
  $nodeIp = ('{0}.{1}.{2}.{3}' -f $startParts[0], $startParts[1], $startParts[2], ([int]$startParts[3] + ($Index - 1)))

  $unattend = New-ApexUnattendXml -ComputerName $name `
    -AdminPassword ($LocalAdminCredential.GetNetworkCredential().Password) `
    -OutputPath (Join-Path $paths.AnswerDir "$name-unattend.xml")

  New-ApexNestedVM -VmName $name -BaseVhdxPath $AzureLocalBaseVhdx `
    -VmDiffDiskDir $paths.VmVhdDir -VmConfigDir $paths.VmDir -SwitchName $net.SwitchName `
    -MemoryMB $c.NodeMemoryMB -CpuCount $c.NodeCpuCount -UnattendPath $unattend `
    -ImdsAddress $net.ImdsAddress -EnableTpm | Out-Null

  # Azure Local virtual deployments require blank capacity disks in addition to
  # the OS disk. Differencing disks are not valid S2D capacity devices.
  for ($dataDiskIndex = 1; $dataDiskIndex -le $c.DataDiskCount; $dataDiskIndex++) {
    $dataDiskPath = Join-Path $paths.VmVhdDir "${name}-data${dataDiskIndex}.vhdx"
    if (Test-Path $dataDiskPath) {
      Remove-Item -Path $dataDiskPath -Force
    }
    New-VHD -Path $dataDiskPath -SizeBytes ($c.DataDiskSizeGB * 1GB) -Dynamic | Out-Null
    Add-VMHardDiskDrive -VMName $name -Path $dataDiskPath
  }

  # Deterministic MACs let the guest map Hyper-V adapter names without relying on
  # enumeration order. The virtual deployment guidance requires spoofing, teaming,
  # and trunk mode so Network ATC can create the management and storage intents.
  $fabricMac = ('0EAA0001{0:D4}' -f $Index)
  $storageAMac = ('0EAA0002{0:D4}' -f $Index)
  $storageBMac = ('0EAA0003{0:D4}' -f $Index)

  $fabricAdapter = Get-VMNetworkAdapter -VMName $name | Select-Object -First 1
  Rename-VMNetworkAdapter -VMNetworkAdapter $fabricAdapter -NewName $c.FabricAdapter
  Set-VMNetworkAdapter -VMName $name -Name $c.FabricAdapter -StaticMacAddress $fabricMac

  Add-VMNetworkAdapter -VMName $name -SwitchName $net.SwitchName `
    -Name $c.StorageAdapterA -StaticMacAddress $storageAMac
  Add-VMNetworkAdapter -VMName $name -SwitchName $net.SwitchName `
    -Name $c.StorageAdapterB -StaticMacAddress $storageBMac

  $nodeAdapters = Get-VMNetworkAdapter -VMName $name
  $nodeAdapters | Set-VMNetworkAdapter -MacAddressSpoofing On -AllowTeaming On
  $nodeAdapters | Set-VMNetworkAdapterVlan -Trunk -NativeVlanId 0 -AllowedVlanIdList '0-1000'
  foreach ($nodeAdapter in $nodeAdapters) {
    # The fabric adapter already carries these rules from New-ApexNestedVM.
    Add-ApexImdsDenyAcl -VMNetworkAdapter $nodeAdapter -RemoteIPAddress $net.ImdsAddress
  }

  $attachedDisks = @(Get-VMHardDiskDrive -VMName $name)
  if ($attachedDisks.Count -ne ($c.DataDiskCount + 1)) {
    throw "Node '$name' has $($attachedDisks.Count) attached disks; expected one OS disk plus $($c.DataDiskCount) capacity disks."
  }

  Start-VM -Name $name
  Wait-ApexVMReady -VmName $name -Credential $LocalAdminCredential | Out-Null

  Write-ApexLog "Configuring node '$name' management IP $nodeIp."
  Invoke-Command -VMName $name -Credential $LocalAdminCredential -ScriptBlock {
    param($ip, $prefix, $gw, $dns, $adapterMap, $fabricName, $storageNames, $expectedDataDisks)

    foreach ($mapping in $adapterMap) {
      $guestAdapter = Get-NetAdapter -Physical | Where-Object {
        ($_.MacAddress -replace '[:-]', '') -eq $mapping.MacAddress
      } | Select-Object -First 1
      if (-not $guestAdapter) {
        throw "Could not find guest adapter with MAC $($mapping.MacAddress)."
      }
      if ($guestAdapter.Name -ne $mapping.Name) {
        $guestAdapter | Rename-NetAdapter -NewName $mapping.Name
      }
      Set-NetIPInterface -InterfaceAlias $mapping.Name -Dhcp Disabled -ErrorAction Stop
    }

    New-NetIPAddress -InterfaceAlias $fabricName -IPAddress $ip -PrefixLength $prefix `
      -DefaultGateway $gw -AddressFamily IPv4 -ErrorAction Stop | Out-Null
    Set-DnsClientServerAddress -InterfaceAlias $fabricName -ServerAddresses $dns

    foreach ($storageName in $storageNames) {
      Set-DnsClient -InterfaceAlias $storageName -RegisterThisConnectionsAddress $false
    }

    $poolableDisks = @(Get-PhysicalDisk -CanPool $true)
    if ($poolableDisks.Count -lt $expectedDataDisks) {
      throw "Only $($poolableDisks.Count) capacity disks can pool; expected at least $expectedDataDisks."
    }
  } -ArgumentList @(
    $nodeIp,
    $net.PrefixLength,
    $net.Gateway,
    $net.DnsServers[0],
    @(
      [pscustomobject]@{ Name = $c.FabricAdapter; MacAddress = $fabricMac }
      [pscustomobject]@{ Name = $c.StorageAdapterA; MacAddress = $storageAMac }
      [pscustomobject]@{ Name = $c.StorageAdapterB; MacAddress = $storageBMac }
    ),
    $c.FabricAdapter,
    @($c.StorageAdapterA, $c.StorageAdapterB),
    $c.DataDiskCount
  )

  $firmware = Get-VMFirmware -VMName $name
  # Hyper-V exposes vTPM state through Get-VMSecurity; no dedicated TPM getter exists.
  $security = Get-VMSecurity -VMName $name
  if ($firmware.SecureBoot -ne 'On' -or -not $security.TpmEnabled) {
    throw "Node '$name' must have Secure Boot and vTPM enabled."
  }

  Set-ApexNodeTimeSync -VmName $name -Credential $LocalAdminCredential -DcIpAddress $Config.Domain.DcIpAddress

  Write-ApexLog "Node '$name' ready at $nodeIp."
  return [pscustomobject]@{ Name = $name; IpAddress = $nodeIp }
}

function ConvertFrom-ApexReportJson {
  <#
  .SYNOPSIS Parse an Environment Checker report without case-folding its keys.
  .DESCRIPTION
    Windows PowerShell's ConvertFrom-Json compares object keys case-insensitively and
    throws when one object carries both 'value' and 'Value'. The Software validator
    emits exactly that, hundreds of times. JavaScriptSerializer compares keys
    ordinally, so it preserves both and returns nested IDictionary/object[] graphs.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Path
  )

  Add-Type -AssemblyName System.Web.Extensions
  $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $serializer.MaxJsonLength = [int]::MaxValue
  $serializer.RecursionLimit = 512
  return $serializer.DeserializeObject((Get-Content -Path $Path -Raw))
}

function Get-ApexCriticalValidationResult {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline)] [object]$InputObject,
    [int]$Depth = 0
  )

  process {
    # Validation reports embed primitives whose own properties recurse forever -
    # [datetime].Date returns a [datetime] - so never descend into value types, and
    # bound the walk as a second guard against unexpectedly deep report graphs.
    if ($null -eq $InputObject -or $Depth -gt 16) {
      return
    }
    if ($InputObject -is [string] -or $InputObject -is [valuetype]) {
      return
    }

    # Severity and Status are strings in some report sections and enum ordinals in
    # others ('2' = Critical, '0' = success). Normalise both shapes, otherwise the
    # gate silently finds nothing and stops blocking.
    $criticalSeverities = @('Critical', '2')
    $passedStatuses = @('Succeeded', 'Success', 'Passed', '0')

    # Reports parsed case-sensitively arrive as dictionaries, which are also
    # IEnumerable; handle them before the collection branch so keys are not walked
    # as KeyValuePair objects.
    if ($InputObject -is [System.Collections.IDictionary]) {
      $keys = @($InputObject.Keys)
      $severityValue = if ($keys -contains 'Severity') { [string]$InputObject['Severity'] } else { $null }
      $statusValue = if ($keys -contains 'Status') { [string]$InputObject['Status'] } else { $null }
      if ($severityValue -in $criticalSeverities -and
        $statusValue -notin $passedStatuses) {
        $identifier = $null
        foreach ($propertyName in @('Name', 'TestName', 'Title')) {
          if ($keys -contains $propertyName -and $InputObject[$propertyName]) {
            $identifier = $InputObject[$propertyName]
            break
          }
        }
        if (-not $identifier) { $identifier = 'UnknownCriticalTest' }
        [pscustomobject]@{
          Name   = [string]$identifier
          Status = [string]$statusValue
        }
      }
      foreach ($key in $keys) {
        if ($key -notin @('Severity', 'Status', 'Name', 'TestName', 'Title')) {
          Get-ApexCriticalValidationResult -InputObject $InputObject[$key] -Depth ($Depth + 1)
        }
      }
      return
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and
      $InputObject -isnot [System.Management.Automation.PSCustomObject]) {
      foreach ($item in $InputObject) {
        Get-ApexCriticalValidationResult -InputObject $item -Depth ($Depth + 1)
      }
      return
    }

    $properties = $InputObject.PSObject.Properties
    $severity = $properties['Severity']
    $status = $properties['Status']
    if ($severity -and $status -and [string]$severity.Value -in $criticalSeverities -and
      [string]$status.Value -notin $passedStatuses) {
      $identifier = foreach ($propertyName in @('Name', 'TestName', 'Title')) {
        if ($properties[$propertyName] -and $properties[$propertyName].Value) {
          $properties[$propertyName].Value
          break
        }
      }
      if (-not $identifier) { $identifier = 'UnknownCriticalTest' }
      [pscustomobject]@{
        Name   = [string]$identifier
        Status = [string]$status.Value
      }
    }

    foreach ($property in $properties) {
      if ($property.Name -notin @('Severity', 'Status', 'Name', 'TestName', 'Title')) {
        Get-ApexCriticalValidationResult -InputObject $property.Value -Depth ($Depth + 1)
      }
    }
  }
}

function Set-ApexNodeNameResolution {
  <#
  .SYNOPSIS Pin the nested node names to their management addresses on the host.
  .DESCRIPTION
    The nodes are still workgroup machines during readiness, so the nested DC holds
    no records for them and the host falls back to LLMNR. LLMNR answers with whichever
    adapter replies first, which is an APIPA address on a storage adapter, so the
    network validator opens its sessions to 169.254.x.x and fails. Explicit hosts
    entries make resolution deterministic; the hosts file is consulted before both
    DNS and LLMNR. The block is rewritten in place so repeated runs cannot stack
    duplicate or stale addresses.
  #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)] [array]$Nodes,
    [Parameter(Mandatory)] [string]$DomainFqdn
  )

  $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
  $beginMarker = '# BEGIN ApexLocal nested nodes'
  $endMarker = '# END ApexLocal nested nodes'

  $existing = @(Get-Content -Path $hostsPath -ErrorAction SilentlyContinue)
  $kept = [System.Collections.Generic.List[string]]::new()
  $inBlock = $false
  foreach ($line in $existing) {
    if ($line -eq $beginMarker) { $inBlock = $true; continue }
    if ($line -eq $endMarker) { $inBlock = $false; continue }
    if (-not $inBlock) { $kept.Add($line) }
  }

  $kept.Add($beginMarker)
  foreach ($node in $Nodes) {
    if (-not $node.IpAddress) {
      throw "Node '$($node.Name)' has no management address to pin."
    }
    $kept.Add("$($node.IpAddress)`t$($node.Name) $($node.Name).$DomainFqdn")
  }
  $kept.Add($endMarker)

  if ($PSCmdlet.ShouldProcess($hostsPath, 'Pin nested node addresses')) {
    Set-Content -Path $hostsPath -Value $kept -Encoding ASCII -Force
  }
  Write-ApexLog "Pinned $($Nodes.Count) nested node name(s) to their management addresses."
}

function Set-ApexNodeWinRmTrust {
  <#
  .SYNOPSIS Let the workgroup host authenticate to the nested nodes over WinRM.
  .DESCRIPTION
    The Environment Checker's network validator opens its own remote sessions to each
    node by name instead of reusing the PowerShell Direct session it is handed, so
    passing -PSSession is not enough. The outer host is not domain-joined, so WinRM
    refuses NTLM to a host that is not trusted. Trust is granted to the exact node
    names, FQDNs, and addresses only. The '*' wildcard is never used, and is stripped
    if something else set it, because it would let the host authenticate to anything.
  #>
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)] [array]$Nodes,
    [Parameter(Mandatory)] [string]$DomainFqdn
  )

  if ((Get-Service -Name WinRM).Status -ne 'Running') {
    Start-Service -Name WinRM
  }

  $wanted = foreach ($node in $Nodes) {
    $node.Name
    "$($node.Name).$DomainFqdn"
    if ($node.IpAddress) { $node.IpAddress }
  }

  $trustedHostsPath = 'WSMan:\localhost\Client\TrustedHosts'
  $current = @((Get-Item -Path $trustedHostsPath).Value -split ',' |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -ne '*' })
  $merged = @(@($current) + @($wanted) | Sort-Object -Unique)

  if (Compare-Object -ReferenceObject $current -DifferenceObject $merged) {
    if ($PSCmdlet.ShouldProcess($trustedHostsPath, 'Trust the nested cluster nodes')) {
      Set-Item -Path $trustedHostsPath -Value ($merged -join ',') -Force
    }
  }
  Write-ApexLog "WinRM TrustedHosts holds $($merged.Count) explicit nested-node entries."
}

function Test-ApexEnvironmentReadiness {
  <#
  .SYNOPSIS Run the standalone Azure Local readiness validators before Arc onboarding.
  .DESCRIPTION
    Runs the pinned Microsoft Environment Checker from the outer host against
    PowerShell Direct sessions for all three nodes. Each validator's raw JSON
    report is copied to the private build-log tree before critical findings stop
    the deployment. Only exact test IDs listed in the configuration can be waived.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [string]$SubscriptionId,
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$ClusterName,
    [Parameter(Mandatory)] [array]$Nodes,
    [Parameter(Mandatory)] [pscredential]$LocalAdminCredential,
    [Parameter(Mandatory)] [pscredential]$DomainAdminCredential,
    # ArcIntegration inspects the Arc machine resources, which only exist after node
    # onboarding, so it cannot run in the same pass as the validators that must pass
    # before onboarding. Running it early failed on four criticals for the sole reason
    # that zero Arc machines existed yet.
    # The split is about WHERE a validator runs, not when. ArcIntegration only works on
    # the Azure Local OS, so it runs in a node session; everything else runs on the host.
    # It is a PRE-registration check: it verifies the resource group is clean, so it must
    # run before Arc onboarding, not after.
    [ValidateSet('HostChecks', 'ArcIntegration')] [string]$Phase = 'HostChecks',
    # Only used by the PostArc phase: the Azure Local instance region the Arc machines
    # and cluster resource live in, which is not the infrastructure region.
    [string]$InstanceLocation
  )

  $moduleVersions = Import-PowerShellDataFile `
    -Path (Join-Path $Config.Paths.RootDir 'ModuleVersions.psd1')
  $checkerVersion = $moduleVersions.AzStackHciEnvironmentChecker
  if (-not (Get-Module -ListAvailable -Name AzStackHci.EnvironmentChecker |
      Where-Object Version -eq ([version]$checkerVersion))) {
    Install-Module -Name AzStackHci.EnvironmentChecker -RequiredVersion $checkerVersion `
      -Repository PSGallery -Scope AllUsers -Force
  }
  Import-Module AzStackHci.EnvironmentChecker -RequiredVersion $checkerVersion -Force

  $reportDirectory = Join-Path $Config.Paths.LogsDir 'EnvironmentChecker'
  New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
  $sourceReport = Join-Path $HOME '.AzStackHci\AzStackHciEnvironmentReport.json'
  $allowedCriticalTests = @($Config.Validation.AllowedCriticalTests)
  $validationSummary = @()
  $nodeSessions = @()

  # The outer host must resolve the nested forest for the AD validator.
  $managementAlias = "vEthernet ($($Config.Network.SwitchName))"
  Set-DnsClientServerAddress -InterfaceAlias $managementAlias `
    -ServerAddresses $Config.Domain.DcIpAddress

  # The network validator ignores the session it is given and dials the nodes itself.
  Set-ApexNodeNameResolution -Nodes $Nodes -DomainFqdn $Config.Domain.Fqdn
  Set-ApexNodeWinRmTrust -Nodes $Nodes -DomainFqdn $Config.Domain.Fqdn

  # Those network sessions authenticate with NTLM, which rejects a bare 'Administrator'
  # against a workgroup node (SEC_E_UNKNOWN_CREDENTIALS, 0x8009030d): the account has to
  # be machine-qualified. '.\' resolves on whichever node is being dialled, so one
  # credential stays valid for all of them, unlike '<nodename>\'. PowerShell Direct is
  # left on the original credential because it is already proven.
  $networkAdminCredential = New-Object System.Management.Automation.PSCredential(
    ".\$(($LocalAdminCredential.UserName -split '\\')[-1])", $LocalAdminCredential.Password)

  # Readiness can begin before every freshly built node has converged on the DC clock.
  # AzStackHci_Software_NtpServer-Sync then reports "NTP Response not received from
  # 'Local CMOS Clock'" for the laggards while the already-converged node passes, which
  # reads like a configuration fault but is purely a race: the stragglers correct
  # themselves minutes later. Wait for all of them before any validator runs.
  if ($Phase -eq 'HostChecks') {
    $timeDeadline = (Get-Date).AddMinutes(15)
    $pending = @()
    do {
      $pending = @()
      foreach ($node in $Nodes) {
        $state = ''
        try {
          $state = Invoke-Command -ComputerName $node.Name -Credential $networkAdminCredential `
            -ScriptBlock { (w32tm /query /status 2>&1) | Out-String } -ErrorAction Stop
        }
        catch { $state = '' }
        $sourceOk = $state -match 'Source:\s*(?!Local CMOS Clock)\S'
        $syncOk = ($state -match 'Last Successful Sync Time:') -and
        ($state -notmatch 'Last Successful Sync Time:\s*unspecified')
        if (-not ($sourceOk -and $syncOk)) { $pending += $node.Name }
      }
      if ($pending.Count -gt 0) {
        Write-ApexLog "Waiting for node clock sync: $($pending -join ', ')." -Level WARN
        Start-Sleep -Seconds 30
      }
    } while ($pending.Count -gt 0 -and (Get-Date) -lt $timeDeadline)

    if ($pending.Count -gt 0) {
      throw "Nodes did not converge on the domain clock within 15 minutes: $($pending -join ', ')."
    }
    Write-ApexLog 'All nodes report a successful time sync against the domain controller.'
  }

  function Reset-ApexNodeSession {
    <#
      Returns a fresh WinRM session per node.

      These must be WinRM sessions, not PowerShell Direct: the checker's
      EnvValidatorNwkLibEnsureTestSessionOpen rebuilds every session it is handed from
      $session.ComputerName plus $session.Runspace.ConnectionInfo.Credential, and a
      PowerShell Direct session carries no reusable credential there, so the rebuild fell
      back to the implicit identity - SYSTEM, which holds no network credential - and
      failed with 0x8009030d after a silent 60x10s retry loop.

      That same helper calls Remove-PSSession on the originals and keeps the replacements
      for itself, so whatever is handed to one validator is Closed by the time the next
      one runs. Every step that needs sessions therefore gets a new set.
    #>
    param()
    $nodeSessions | Remove-PSSession -ErrorAction SilentlyContinue
    $fresh = @()
    foreach ($node in $Nodes) {
      # A freshly rebuilt node can still reboot while specializing, which leaves a session
      # in the Broken state and fails the next validator with a confusing session error.
      # Open the session, prove it actually executes, and retry if it does not.
      $session = $null
      for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
          $candidate = New-PSSession -ComputerName $node.Name `
            -Credential $networkAdminCredential -ErrorAction Stop
          $null = Invoke-Command -Session $candidate -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
          if ($candidate.State -ne 'Opened') {
            throw "session state is $($candidate.State)"
          }
          $session = $candidate
          break
        }
        catch {
          if ($candidate) { Remove-PSSession -Session $candidate -ErrorAction SilentlyContinue }
          Write-ApexLog "Session to '$($node.Name)' not usable yet ($attempt/10): $($_.Exception.Message)" -Level WARN
          Start-Sleep -Seconds 30
        }
      }
      if (-not $session) {
        throw "Could not open a usable WinRM session to '$($node.Name)' after 10 attempts."
      }
      $fresh += $session
    }
    return $fresh
  }

  function Invoke-ValidationStep {
    param(
      [Parameter(Mandatory)] [string]$Name,
      [Parameter(Mandatory)] [scriptblock]$Operation,
      # Most validators drop their report in the caller's profile. The network validator
      # honours -OutputPath and writes it there instead, so the report location has to be
      # told to this helper rather than assumed.
      [string]$ReportPath = $sourceReport
    )

    Remove-Item -Path $ReportPath -Force -ErrorAction SilentlyContinue
    & $Operation
    if (-not (Test-Path $ReportPath)) {
      throw "Environment Checker '$Name' did not write its JSON report to '$ReportPath'."
    }

    $destination = Join-Path $reportDirectory `
    ("{0}-{1}.json" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -Path $ReportPath -Destination $destination -Force
    $report = ConvertFrom-ApexReportJson -Path $destination
    $criticalResults = @(Get-ApexCriticalValidationResult -InputObject $report)
    $blockedResults = @($criticalResults | Where-Object Name -notin $allowedCriticalTests)

    $validationSummary += [pscustomobject]@{
      Validator       = $Name
      CriticalCount   = $criticalResults.Count
      BlockedCount    = $blockedResults.Count
      CriticalTestIds = @($criticalResults.Name)
    }
    if ($blockedResults.Count -gt 0) {
      $blockedNames = $blockedResults.Name -join ', '
      throw "Environment Checker '$Name' reported blocking critical findings: $blockedNames."
    }
    Write-ApexLog "Environment Checker '$Name' passed with $($criticalResults.Count) waived critical finding(s)."
  }

  try {
    if ($Phase -eq 'ArcIntegration') {
      # This validator only runs on the Azure Local OS. Executed on the outer Windows
      # Server host every check returns "ARC Integration validation is only supported on
      # HCI OS", and Get-AzureStackHCISubscriptionStatus does not exist there at all.
      # Run it inside a node session and copy its report back to the host log tree.
      Import-Module Az.Accounts -ErrorAction Stop
      $rawToken = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -ErrorAction Stop
      $armToken = if ($rawToken.Token -is [System.Security.SecureString]) {
        [System.Net.NetworkCredential]::new('', $rawToken.Token).Password
      }
      else { [string]$rawToken.Token }
      $accountId = $null
      try { $accountId = (Get-AzContext).Account.Id } catch { $accountId = $null }
      if (-not $accountId) {
        throw 'Could not resolve the host account id; the Arc integration validator requires it.'
      }
      $tenant = [Environment]::GetEnvironmentVariable('APEX_TenantId', 'Machine')
      $nodeNames = @($Nodes.Name)
      $arcReportPath = Join-Path $reportDirectory 'ArcIntegration-node.json'

      try {
        $nodeSessions = Reset-ApexNodeSession
        $arcSession = $nodeSessions[0]

        # The validator calls Get-AzResource internally, and the Azure Local image ships
        # Az.Accounts but not Az.Resources, so it fails with CommandNotFoundException.
        # Side-load the pinned pair from the host: the node has no PSGallery, and these
        # two versions are the combination the host itself runs.
        $guestStaging = Join-Path $Config.Paths.RootDir 'GuestModules'
        foreach ($guestModule in @(
            @{ Name = 'Az.Accounts'; Version = $moduleVersions.AzAccounts }
            @{ Name = 'Az.Resources'; Version = $moduleVersions.AzResources }
          )) {
          Install-ApexGuestModule -Name $guestModule.Name -RequiredVersion $guestModule.Version `
            -Session $arcSession -StagingPath $guestStaging
        }

        Invoke-ValidationStep -Name 'ArcIntegration' -ReportPath $arcReportPath -Operation {
          $remoteReport = Invoke-Command -Session $arcSession -ScriptBlock {
            param($subId, $tenantId, $rg, $region, $names, $token, $account)
            Import-Module AzStackHci.EnvironmentChecker -Force -ErrorAction Stop
            $outputDir = Join-Path $env:TEMP 'ApexArcIntegration'
            New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
            # Supplying ArmAccessToken selects the ARMToken parameter set, which also
            # makes AzureEnvironment and AccountId mandatory. Omitting either prompts,
            # and a prompt inside a remote session is invisible.
            $arguments = @{
              AzureEnvironment              = 'AzureCloud'
              SubscriptionID                = $subId
              TenantID                      = $tenantId
              AccountId                     = $account
              ArcResourceGroupName          = $rg
              RegistrationResourceGroupName = $rg
              Region                        = $region
              NodeNames                     = $names
              ArmAccessToken                = $token
              OutputPath                    = $outputDir
            }
            # Fail loudly rather than let PowerShell prompt for anything still missing.
            $command = Get-Command Invoke-AzStackHciArcIntegrationValidation -ErrorAction Stop
            $armTokenSet = $command.ParameterSets | Where-Object { $_.Name -eq 'ARMToken' }
            $missing = @($armTokenSet.Parameters |
              Where-Object { $_.IsMandatory -and -not $arguments.ContainsKey($_.Name) } |
              ForEach-Object { $_.Name })
            if ($missing) {
              throw ("Invoke-AzStackHciArcIntegrationValidation ARMToken set also requires: " +
                ($missing -join ', '))
            }
            try {
              Invoke-AzStackHciArcIntegrationValidation @arguments -ErrorAction Stop | Out-Null
            }
            finally {
              $arguments.ArmAccessToken = $null
              $token = $null
            }
            return (Join-Path $outputDir 'AzStackHciEnvironmentReport.json')
          } -ArgumentList $SubscriptionId, $tenant, $ResourceGroup, $InstanceLocation,
          $nodeNames, $armToken, $accountId

          Copy-Item -FromSession $arcSession -Path $remoteReport `
            -Destination $arcReportPath -Force
        }
      }
      finally {
        $armToken = $null
      }

      $arcSummaryPath = Join-Path $reportDirectory 'validation-summary-ArcIntegration.json'
      $validationSummary | ConvertTo-Json -Depth 5 | Set-Content -Path $arcSummaryPath -Encoding UTF8
      return
    }

    $nodeSessions = Reset-ApexNodeSession
    Invoke-ValidationStep -Name 'Connectivity' -Operation {
      Invoke-AzStackHciConnectivityValidation -PsSession $nodeSessions -ErrorAction Stop | Out-Null
    }
    $nodeSessions = Reset-ApexNodeSession
    Invoke-ValidationStep -Name 'Software' -Operation {
      Invoke-AzStackHciSoftwareValidation -PsSession $nodeSessions `
        -Exclude Test-IsNotPartofDomain -ErrorAction Stop | Out-Null
    }
    Invoke-ValidationStep -Name 'ActiveDirectory' -Operation {
      # The isolated lab has no NetBIOS name resolution, so Kerberos rejects
      # DOMAIN\user here; the validator must authenticate with a UPN.
      $adUserName = ($DomainAdminCredential.UserName -split '\\')[-1]
      $adCredential = New-Object System.Management.Automation.PSCredential(
        "$adUserName@$($Config.Domain.Fqdn)", $DomainAdminCredential.Password)
      Invoke-AzStackHciExternalActiveDirectoryValidation `
        -ADOUPath $Config.Domain.OuPath `
        -DomainFQDN $Config.Domain.Fqdn `
        -NamingPrefix $Config.Domain.NamingPrefix `
        -ActiveDirectoryServer $Config.Domain.Fqdn `
        -ActiveDirectoryCredentials $adCredential `
        -ClusterName $ClusterName `
        -PhysicalMachineNames ($Nodes.Name -join ',') `
        -ErrorAction Stop | Out-Null
    }

    $ipPools = New-Object System.Collections.ArrayList
    $null = $ipPools.Add([pscustomobject]@{
        StartingAddress = $Config.Cluster.StartingIp
        EndingAddress   = $Config.Cluster.EndingIp
      })
    # The checker hard-casts the three override flags, e.g.
    # [Boolean] $x = $currentIntent.OverrideAdapterProperty, so omitting them fails with
    # 'Cannot convert value "" to type System.Boolean' rather than anything diagnostic.
    # All three are $false because Get-NetAdapterRdma reports every nested adapter with
    # Enabled=False, which is the checker's valid "no RDMA, no override" combination and
    # matches the intent list the cluster deployment sends.
    $atcHostIntents = @(
      [pscustomobject]@{
        name                                = 'Compute_Management'
        trafficType                         = @('Management', 'Compute')
        adapter                             = @($Config.Cluster.FabricAdapter)
        OverrideAdapterProperty             = $false
        AdapterPropertyOverrides            = $null
        OverrideQoSPolicy                   = $false
        QoSPolicyOverrides                  = $null
        OverrideVirtualSwitchConfiguration  = $false
        VirtualSwitchConfigurationOverrides = $null
      }
      [pscustomobject]@{
        name                                = 'Storage'
        trafficType                         = @('Storage')
        adapter                             = @($Config.Cluster.StorageAdapterA, $Config.Cluster.StorageAdapterB)
        OverrideAdapterProperty             = $false
        AdapterPropertyOverrides            = $null
        OverrideQoSPolicy                   = $false
        QoSPolicyOverrides                  = $null
        OverrideVirtualSwitchConfiguration  = $false
        VirtualSwitchConfigurationOverrides = $null
      }
    )
    $nodeSessions = Reset-ApexNodeSession
    Invoke-ValidationStep -Name 'Network' -ReportPath (Join-Path $reportDirectory 'AzStackHciEnvironmentReport.json') -Operation {
      # NodesInCluster is mandatory on this parameter set and is a count, not names.
      # Omitting it makes PowerShell prompt, which blocks the build indefinitely.
      Invoke-AzStackHciNetworkValidation -IpPools $ipPools `
        -ManagementSubnetValue $Config.Network.SubnetPrefix `
        -PSSession $nodeSessions `
        -NodesInCluster ([int16]$Nodes.Count) `
        -ConnectionLocalAdminCredential $networkAdminCredential `
        -OutputPath $reportDirectory `
        -AtcHostIntents $atcHostIntents `
        -ErrorAction Stop | Out-Null
    }
    $nodeSessions = Reset-ApexNodeSession
    Invoke-ValidationStep -Name 'Hardware' -Operation {
      Invoke-AzStackHciHardwareValidation -PsSession $nodeSessions -ErrorAction Stop | Out-Null
    }

    $summaryPath = Join-Path $reportDirectory 'validation-summary-HostChecks.json'
    $validationSummary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8
  }
  finally {
    $nodeSessions | Remove-PSSession -ErrorAction SilentlyContinue
    Remove-Module AzStackHci.EnvironmentChecker -Force -ErrorAction SilentlyContinue
  }
}

function Connect-ApexNodeToArc {
  <#
  .SYNOPSIS Run the supported Azure Local Arc initialization on a node.
  .DESCRIPTION
    Invokes the Azure Local OS-bundled Invoke-AzStackHciArcInitialization command,
    which owns Arc registration and edge bootstrap for current 2505+ releases.
    Bare azcmagent onboarding is intentionally unsupported because it does not
    establish the Azure Local bootstrap state required for cloud deployment.

    The nested node has no managed identity, so the host acquires a short-lived ARM
    token with its system-assigned identity and transfers it only over PowerShell
    Direct. The token is cleared in both host and guest scopes after initialization.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [pscredential]$Credential,
    [Parameter(Mandatory)] [string]$SubscriptionId,
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$Location,
    # Arc initialization normally takes 5-15 minutes. The bound exists because the
    # command falls back to an interactive device-code prompt if it ever rejects the
    # token, and that prompt is invisible over PowerShell Direct: without a timeout
    # the build would block until the whole run command expires.
    [int]$TimeoutSeconds = 2700
  )
  # Acquire an ARM access token on the HOST using its managed identity. Handle both
  # the legacy plaintext .Token and the newer -AsSecureString Az.Accounts behavior.
  Import-Module Az.Accounts -ErrorAction Stop
  $raw = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -ErrorAction Stop
  if ($raw.Token -is [System.Security.SecureString]) {
    $accessToken = [System.Net.NetworkCredential]::new('', $raw.Token).Password
  }
  else {
    $accessToken = [string]$raw.Token
  }
  if (-not $accessToken) { throw "Could not obtain an ARM access token from the host managed identity for '$VmName'." }

  try {
    Write-ApexLog "Running Azure Local Arc initialization on '$VmName' in $ResourceGroup ($Location)."
    $arcJob = Invoke-Command -VMName $VmName -Credential $Credential -AsJob -ScriptBlock {
      param(
        [string]$subId,
        [string]$rg,
        [string]$tenant,
        [string]$loc,
        [string]$token
      )

      $command = Get-Command Invoke-AzStackHciArcInitialization -ErrorAction Stop
      $version = if ($command.Module) { $command.Module.Version.ToString() } else { 'OS-bundled' }
      $parameters = @{
        TenantId       = $tenant
        SubscriptionID = $subId
        ResourceGroup  = $rg
        Region         = $loc
        Cloud          = 'AzureCloud'
        ArmAccessToken = $token
      }
      # This command only exists on the Azure Local OS, so the host-side contract gate
      # cannot see it. Verify the surface here, before spending the Arc onboarding time.
      $missing = @($parameters.Keys | Where-Object { -not $command.Parameters.ContainsKey($_) })
      if ($missing) {
        throw "Invoke-AzStackHciArcInitialization does not expose: $($missing -join ', ')."
      }
      try {
        Invoke-AzStackHciArcInitialization @parameters -ErrorAction Stop | Out-Null
      }
      finally {
        $parameters.ArmAccessToken = $null
        $token = $null
      }

      # The command can exit successfully without onboarding anything, observed when
      # residual agent state survives a disconnect. Trusting its exit code turned that
      # into a silent no-op that only surfaced 30 minutes later as "discovered 0".
      # Resolve the binary explicitly: a fresh remote session does not always carry the
      # installer's PATH update, so a bare 'azcmagent' can fail as command-not-found.
      $azcmagent = Get-Command azcmagent -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty Source -First 1
      if (-not $azcmagent) {
        $azcmagent = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
      }
      if (-not (Test-Path -LiteralPath $azcmagent)) {
        throw "Cannot locate azcmagent to confirm the Arc connection state ('$azcmagent')."
      }
      $agentState = (& $azcmagent show 2>&1 | Out-String)
      if ($agentState -notmatch 'Agent Status\s*:\s*Connected') {
        throw ('Arc initialization reported success but the agent is not Connected. ' +
          'Residual agent state makes the command a silent no-op; disconnect the agent ' +
          'and retry, or rebuild the node.')
      }
      return $version
    } -ArgumentList $SubscriptionId, $ResourceGroup, $TenantId, $Location, $accessToken

    if (-not (Wait-Job -Job $arcJob -Timeout $TimeoutSeconds)) {
      Stop-Job -Job $arcJob -ErrorAction SilentlyContinue
      Remove-Job -Job $arcJob -Force -ErrorAction SilentlyContinue
      throw ("Arc initialization on '$VmName' exceeded $TimeoutSeconds seconds. " +
        'The node is most likely blocked on an invisible device-code prompt because the ' +
        'ARM token was rejected; confirm the host managed identity can still reach Azure.')
    }
    $bootstrapVersion = Receive-Job -Job $arcJob -ErrorAction Stop
    Remove-Job -Job $arcJob -Force -ErrorAction SilentlyContinue
    Write-ApexLog "Azure Local Arc initialization completed on '$VmName' (command version $bootstrapVersion)."
  }
  finally {
    $accessToken = $null
    $raw = $null
  }
}

#endregion

#region ---------------------------------------------------------------- Cluster

function Start-ApexLocalClusterDeployment {
  <#
  .SYNOPSIS Validate then deploy the Azure Local cluster via the ARM template.
  .DESCRIPTION
    Builds the FULL create-cluster parameter set (the LocalBox flow does this via
    Generate-ARM-Template.ps1 string-replacement; we pass a hashtable directly to
    New-AzResourceGroupDeployment, which is cleaner and less brittle):
      • physicalNodesSettings  from the node name + management IP of each node,
      • intentList             Compute_Management (FABRIC) + Storage (StorageA/B),
      • storageNetworkList      StorageA/StorageB with the configured VLAN ids,
      • generated names         Key Vault, witness + diagnostics storage accounts,
      • domain/IP/security      FQDN, OU path, contiguous mgmt IP block, defaults.
    Runs 'Validate' then 'Deploy' against artifacts/selfhosted/azlocal.json (the
    proven Microsoft create-cluster template, vendored into this repo). The in-VM
    host identity holds Contributor + User Access Administrator on the RG (assigned
    in main.bicep) so the template's role assignments succeed.

    The pinned 2505+ template uses AzureStackLCMAdminPassword and the self-hosted
    patch removes the cloud-witness key path because this profile is fixed to
    three nodes with odd quorum.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$ClusterName,
    [Parameter(Mandatory)] [string]$InstanceLocation,
    [Parameter(Mandatory)] [string]$HciResourceProviderObjectId,
    [Parameter(Mandatory)] [string[]]$ArcNodeResourceIds,
    [Parameter(Mandatory)] [array]$Nodes,            # objects: { Name, IpAddress }
    [Parameter(Mandatory)] [pscredential]$LocalAdminCredential,
    [Parameter(Mandatory)] [pscredential]$DomainAdminCredential,
    [string]$TemplatePath = 'C:\ApexLocal\azlocal.json',
    [switch]$SkipValidation
  )
  if (-not (Test-Path $TemplatePath)) { throw "Cluster template not found: $TemplatePath" }
  $c = $Config.Cluster
  $dom = $Config.Domain

  # --- physicalNodesSettings: { name, ipv4Address } per node ---
  $physicalNodes = @($Nodes | ForEach-Object {
      @{ name = $_.Name; ipv4Address = $_.IpAddress }
    })

  # --- intentList: converged management/compute + storage (nested lab) ---
  # Nested Hyper-V adapters advertise RDMA capability but the platform reports
  # OperationalState=False, so 'AzStackHci_Network_Test_NetAdapter_RDMA_Operational'
  # fails unless RDMA is explicitly disabled. Setting networkDirect='Disabled' is
  # NOT enough on its own: Network ATC ignores adapterPropertyOverrides entirely
  # unless overrideAdapterProperty is $true.
  $intentList = @(
    @{
      name                                = 'Compute_Management'
      trafficType                         = @('Management', 'Compute')
      adapter                             = @('FABRIC')
      overrideVirtualSwitchConfiguration  = $false
      virtualSwitchConfigurationOverrides = @{ enableIov = ''; loadBalancingAlgorithm = '' }
      overrideQosPolicy                   = $false
      qosPolicyOverrides                  = @{ priorityValue8021Action_Cluster = '7'; priorityValue8021Action_SMB = '3'; bandwidthPercentage_SMB = '50' }
      overrideAdapterProperty             = $true
      adapterPropertyOverrides            = @{ jumboPacket = '9014'; networkDirect = 'Disabled'; networkDirectTechnology = '' }
    },
    @{
      name                                = 'Storage'
      trafficType                         = @('Storage')
      adapter                             = @('StorageA', 'StorageB')
      overrideVirtualSwitchConfiguration  = $false
      virtualSwitchConfigurationOverrides = @{ enableIov = ''; loadBalancingAlgorithm = '' }
      overrideQosPolicy                   = $false
      qosPolicyOverrides                  = @{ priorityValue8021Action_Cluster = '7'; priorityValue8021Action_SMB = '3'; bandwidthPercentage_SMB = '50' }
      overrideAdapterProperty             = $true
      adapterPropertyOverrides            = @{ jumboPacket = '9014'; networkDirect = 'Disabled'; networkDirectTechnology = '' }
    }
  )

  # --- storageNetworkList: StorageA/StorageB with the configured VLANs ---
  $storageNetworkList = @(
    @{ name = 'StorageA'; networkAdapterName = 'StorageA'; vlanId = "$($c.StorageVlanA)" },
    @{ name = 'StorageB'; networkAdapterName = 'StorageB'; vlanId = "$($c.StorageVlanB)" }
  )

  # Recovery must target the same resources created by the first deployment attempt.
  $suffix = [Environment]::GetEnvironmentVariable('APEX_ClusterResourceSuffix', 'Machine')
  if ($suffix -notmatch '^[a-z0-9]{6}$') {
    throw "Invalid deterministic cluster resource suffix '$suffix'."
  }
  $keyVaultName = "apxkv$suffix"
  $diagSa = "apxdiag$suffix"

  $common = @{
    ResourceGroupName             = $ResourceGroup
    TemplateFile                  = $TemplatePath
    clusterName                   = $ClusterName
    location                      = $InstanceLocation
    tenantId                      = [Environment]::GetEnvironmentVariable('APEX_TenantId', 'Machine')
    hciResourceProviderObjectID   = $HciResourceProviderObjectId
    arcNodeResourceIds            = $ArcNodeResourceIds
    domainFqdn                    = $dom.Fqdn
    adouPath                      = $dom.OuPath
    namingPrefix                  = 'apexloc'
    localAdminUserName            = $LocalAdminCredential.UserName
    localAdminPassword            = $LocalAdminCredential.Password
    # The LCM account must be the bare SAM name. Passing 'DOMAIN\user' fails validation
    # with "Domain user credential object cannot contain domain name as part of Username"
    # after every component validator has already passed.
    AzureStackLCMAdminUsername    = ($DomainAdminCredential.UserName -split '\\')[-1]
    AzureStackLCMAdminPassword    = $DomainAdminCredential.Password
    keyVaultName                  = $keyVaultName
    diagnosticStorageAccountName  = $diagSa
    physicalNodesSettings         = $physicalNodes
    intentList                    = $intentList
    storageNetworkList            = $storageNetworkList
    networkingType                = 'switchedMultiServerDeployment'
    storageConnectivitySwitchless = $false
    enableStorageAutoIp           = $true
    customLocation                = "$ClusterName-cl"
    startingIPAddress             = $c.StartingIp
    endingIPAddress               = $c.EndingIp
    subnetMask                    = $c.SubnetMask
    defaultGateway                = $c.DefaultGateway
    dnsServers                    = @($dom.DcIpAddress)
    witnessType                   = 'No Witness'
    securityLevel                 = 'Recommended'
    configurationMode             = 'Express'
  }

  if (-not $SkipValidation) {
    # A deploymentSettings resource left behind by a failed validation latches the
    # cluster into ValidationFailed and makes every later attempt fail the same way,
    # regardless of whether the underlying problem was fixed. Clear it first so a
    # re-run actually re-validates instead of replaying the previous verdict.
    $settingsId = ("/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroup" +
      "/providers/Microsoft.AzureStackHCI/clusters/$ClusterName/deploymentSettings/default")
    $existingSettings = Get-AzResource -ResourceId $settingsId -ApiVersion '2024-04-01' -ErrorAction SilentlyContinue
    if ($existingSettings) {
      Write-ApexLog "Removing stale deploymentSettings (provisioningState=$($existingSettings.Properties.provisioningState))."
      Remove-AzResource -ResourceId $settingsId -ApiVersion '2024-04-01' -Force -ErrorAction Stop | Out-Null
      Start-Sleep -Seconds 30
    }

    Write-ApexLog "Validating cluster '$ClusterName' (deploymentMode=Validate)..."
    New-AzResourceGroupDeployment @common -deploymentMode 'Validate' `
      -Name "apexlocal-validate-$((Get-Date).ToString('yyyyMMddHHmmss'))" -Verbose -ErrorAction Stop | Out-Null
    Write-ApexLog 'Validation succeeded.'

    # An ARM Validate deployment returning success only means the request was accepted.
    # The validation itself runs asynchronously on the cluster and reports through the
    # deploymentSettings resource, so deploying on the strength of the ARM result alone
    # is rejected with "Deploy Operation is not allowed in Current State[ValidationFailed]".
    # Poll the deploymentSettings resource, which carries the authoritative result and
    # the per-step detail. The cluster resource's own 'status' is not reliably populated
    # and read back empty here, which a wildcard failure test silently accepts. This
    # gate is therefore fail-closed: only an explicit success is allowed through.
    $successStates = @('Success', 'Succeeded')
    $terminalStates = $successStates + @('Error', 'Failed')
    $validationDeadline = (Get-Date).AddMinutes(90)
    $validationState = ''
    $failedSteps = @()
    do {
      Start-Sleep -Seconds 60
      $settings = Get-AzResource -ResourceId $settingsId -ApiVersion '2024-04-01' -ErrorAction SilentlyContinue
      $validation = $settings.Properties.reportedProperties.validationStatus
      $validationState = "$($validation.status)"
      $failedSteps = @($validation.steps |
        Where-Object { "$($_.status)" -notin $successStates } |
        ForEach-Object { "$($_.name) [$(if ($_.status) { $_.status } else { 'did not run' })]" })
      Write-ApexLog "Cluster validation state: '$validationState'; $($failedSteps.Count) step(s) not successful."
    } while ($validationState -notin $terminalStates -and (Get-Date) -lt $validationDeadline)

    if ($validationState -notin $successStates) {
      throw ("Cluster validation did not succeed (state '$validationState'). Steps not " +
        "successful: $($failedSteps -join '; '). The first non-successful step is the real " +
        'failure; read its exception under C:\MASLogs\LCM_Controller_Validate_Exception*.xml ' +
        'on the first node for the remediation text. Then rebuild from the Nodes stage: ' +
        'validation is not idempotent and cannot be retried in place.')
    }
  }

  Set-ApexProgress -ResourceGroup $ResourceGroup -Progress 'ClusterDeploying' `
    -Status "Deploying cluster $ClusterName" -Config $Config
  Write-ApexLog "Deploying cluster '$ClusterName' (deploymentMode=Deploy). This takes ~2.5-3 hours..."
  $deployment = New-AzResourceGroupDeployment @common -deploymentMode 'Deploy' `
    -Name "apexlocal-deploy-$((Get-Date).ToString('yyyyMMddHHmmss'))" -Verbose -ErrorAction Stop
  if ($deployment.ProvisioningState -ne 'Succeeded') {
    throw "Cluster ARM deployment finished in state '$($deployment.ProvisioningState)'."
  }

  $clusterDeadline = (Get-Date).AddMinutes(30)
  do {
    $clusterResource = Get-AzResource -ResourceGroupName $ResourceGroup `
      -ResourceType 'Microsoft.AzureStackHCI/clusters' -Name $ClusterName `
      -ExpandProperties -ErrorAction SilentlyContinue
    $provisioningState = $clusterResource.Properties.provisioningState
    $connectionState = $clusterResource.Properties.status
    if ($provisioningState -ne 'Succeeded' -or $connectionState -ne 'Connected') {
      Write-ApexLog "Waiting for authoritative cluster state: provisioning=$provisioningState status=$connectionState."
      Start-Sleep -Seconds 30
    }
  } while (($provisioningState -ne 'Succeeded' -or $connectionState -ne 'Connected') -and
    (Get-Date) -lt $clusterDeadline)

  if ($provisioningState -ne 'Succeeded' -or $connectionState -ne 'Connected') {
    throw "Cluster '$ClusterName' did not reach Succeeded/Connected (provisioning=$provisioningState status=$connectionState)."
  }
  Write-ApexLog "Cluster '$ClusterName' reached Succeeded/Connected."
}

#endregion

Export-ModuleMember -Function @(
  'Get-ApexConfig', 'Write-ApexLog', 'Connect-ApexAzure', 'Set-ApexProgress', 'Send-ApexLogsToStorage',
  'Clear-ApexBootstrapSecrets',
  'Wait-ApexStagedIso', 'Get-ApexStagedIso', 'Convert-ApexIsoToVhdx',
  'New-ApexHostSwitch', 'New-ApexRouterVM',
  'New-ApexUnattendXml', 'New-ApexNestedVM', 'Wait-ApexVMReady', 'New-ApexDomainController',
  'Test-ApexCommandContract', 'Install-ApexGuestModule',
  'Initialize-ApexActiveDirectory', 'New-ApexLocalNode', 'Test-ApexEnvironmentReadiness',
  'Connect-ApexNodeToArc', 'Set-ApexNodeTimeSync',
  'Start-ApexLocalClusterDeployment'
)
