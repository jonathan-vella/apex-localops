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
    if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $merge[$statusKey] = $Status }
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
    Get-ChildItem -Path $LogDir -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object {
      Set-AzStorageBlobContent -File $_.FullName -Container $Container -Blob "$prefix/$($_.Name)" -Context $ctx -Force | Out-Null
    }
    Write-ApexLog "Uploaded build logs to $StorageAccountName/$Container/$prefix."
  }
  catch {
    Write-ApexLog "Log upload failed (continuing): $($_.Exception.Message)" -Level WARN
  }
}

#endregion

#region ------------------------------------------------------------ Image pipeline

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
      if ($azl -and $ws) {
        Write-ApexLog "Both ISOs present: $AzureLocalIsoBlob ($([math]::Round($azl.Length/1GB,2)) GB), $WindowsServerIsoBlob ($([math]::Round($ws.Length/1GB,2)) GB)."
        return $true
      }
      $missing = @()
      if (-not $azl) { $missing += $AzureLocalIsoBlob }
      if (-not $ws) { $missing += $WindowsServerIsoBlob }
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
  throw "Timed out after $TimeoutMinutes min waiting for both ISOs in $StorageAccountName/$Container."
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
    [Parameter(Mandatory)] [string]$Destination
  )
  Import-Module Az.Storage -ErrorAction Stop
  $dir = Split-Path -Parent $Destination
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

  $remote = Get-AzStorageBlob -Container $Container -Blob $Blob -Context $ctx -ErrorAction Stop
  if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -eq $remote.Length)) {
    Write-ApexLog "ISO already present and correct size: $Destination (skipping download)."
    return $Destination
  }
  Write-ApexLog "Downloading $Container/$Blob ($([math]::Round($remote.Length/1GB,2)) GB) -> $Destination"
  Get-AzStorageBlobContent -Container $Container -Blob $Blob -Destination $Destination -Context $ctx -Force | Out-Null

  $local = (Get-Item $Destination).Length
  if ($local -ne $remote.Length) {
    throw "Downloaded size mismatch for ${Blob}: local=$local remote=$($remote.Length)."
  }
  Write-ApexLog "Downloaded and verified: $Destination ($local bytes)."
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

    NOTE: For Azure Local nodes the OS image must reach the cloud-deployment-ready
    state; applying install.wim produces a clean OS that still completes OOBE on
    first boot. If a given Azure Local build resists offline imaging, the proven
    fallback (used by the SFF profile) is to BOOT the node VM from the ISO with an
    autounattend answer file instead of pre-applying the image - see New-ApexNestedVM
    -BootFromIso. This function is the default (faster re-deploys); the fallback is
    available without code changes.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$IsoPath,
    [Parameter(Mandatory)] [string]$VhdxPath,
    [int]$VhdxSizeGB = 127,
    [string]$ImageName,            # e.g. 'Azure Stack HCI' / 'Windows Server 2025 Datacenter (Desktop Experience)'
    [int]$ImageIndex = 0           # used when ImageName is not supplied
  )
  if (Test-Path $VhdxPath) {
    Write-ApexLog "Base VHDX already exists: $VhdxPath (skipping conversion)."
    return $VhdxPath
  }
  $dir = Split-Path -Parent $VhdxPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

  Write-ApexLog "Mounting ISO: $IsoPath"
  $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
  $isoDrive = ($mount | Get-Volume).DriveLetter
  try {
    $wim = Join-Path "$($isoDrive):" 'sources\install.wim'
    if (-not (Test-Path $wim)) { $wim = Join-Path "$($isoDrive):" 'sources\install.esd' }
    if (-not (Test-Path $wim)) { throw "No install.wim/esd found on the ISO (${isoDrive}:)." }

    # Resolve the image index to apply.
    $idx = $ImageIndex
    if ($ImageName) {
      $img = Get-WindowsImage -ImagePath $wim | Where-Object { $_.ImageName -eq $ImageName }
      if (-not $img) {
        $available = (Get-WindowsImage -ImagePath $wim | ForEach-Object { "[$($_.ImageIndex)] $($_.ImageName)" }) -join '; '
        throw "Image '$ImageName' not found in $wim. Available: $available"
      }
      $idx = $img.ImageIndex
    }
    if (-not $idx -or $idx -lt 1) { $idx = 1 }
    Write-ApexLog "Using image index $idx from $wim."

    # Create and mount the VHDX.
    Write-ApexLog "Creating VHDX: $VhdxPath (${VhdxSizeGB} GB dynamic)"
    New-VHD -Path $VhdxPath -SizeBytes ($VhdxSizeGB * 1GB) -Dynamic | Out-Null
    $disk = Mount-VHD -Path $VhdxPath -Passthru | Get-Disk
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false | Out-Null

    # UEFI layout: ESP (FAT32) + MSR + OS (NTFS).
    $efi = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null
    $efi | Set-Partition -NewDriveLetter 'S' | Out-Null
    New-Partition -DiskNumber $disk.Number -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null  # MSR
    $os = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
    Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'OS' -Confirm:$false | Out-Null
    $os | Set-Partition -NewDriveLetter 'W' | Out-Null

    # Apply the OS image, then write UEFI boot files to the ESP.
    Write-ApexLog "Applying image index $idx to W: (this takes several minutes)..."
    Expand-WindowsImage -ImagePath $wim -Index $idx -ApplyPath 'W:\' -ErrorAction Stop | Out-Null
    Write-ApexLog 'Writing UEFI boot files (bcdboot) to S:...'
    & "$env:SystemRoot\System32\bcdboot.exe" 'W:\Windows' /s 'S:' /f UEFI | Out-Null

    Write-ApexLog "Base VHDX ready: $VhdxPath"
  }
  finally {
    try { Dismount-VHD -Path $VhdxPath -ErrorAction SilentlyContinue } catch { }
    try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
  }
  return $VhdxPath
}

#endregion

#region -------------------------------------------------------------- Host fabric

function New-ApexHostSwitch {
  <#
  .SYNOPSIS Create the internal Hyper-V switch + host NAT for the nested network.
  .DESCRIPTION
    OWNED-SCOPE (fabric): a single internal switch + WinNAT gives the nested DC and
    nodes their management/Arc path on 192.168.1.0/24. Azure Local STORAGE intents
    are provided as ADDITIONAL per-node adapters by New-ApexLocalNode (-StorageVlanA
    /-StorageVlanB), converged on this switch for the nested lab. Idempotent.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$SwitchName,
    [Parameter(Mandatory)] [string]$NatName,
    [Parameter(Mandatory)] [string]$Gateway,
    [Parameter(Mandatory)] [string]$SubnetPrefix,
    [int]$PrefixLength = 24
  )
  if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Creating internal VM switch '$SwitchName'."
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
  }
  $alias = "vEthernet ($SwitchName)"
  $existingIp = Get-NetIPAddress -InterfaceAlias $alias -IPAddress $Gateway -ErrorAction SilentlyContinue
  if (-not $existingIp) {
    Write-ApexLog "Assigning host gateway IP $Gateway/$PrefixLength on '$alias'."
    New-NetIPAddress -InterfaceAlias $alias -IPAddress $Gateway -PrefixLength $PrefixLength | Out-Null
  }
  if (-not (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue)) {
    Write-ApexLog "Creating host NAT '$NatName' for $SubnetPrefix."
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $SubnetPrefix | Out-Null
  }
  Write-ApexLog "Host switch + NAT ready ($SwitchName / $NatName)."
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
  $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$ComputerName</ComputerName>
      <TimeZone>$TimeZone</TimeZone>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>$Locale</InputLocale>
      <SystemLocale>$Locale</SystemLocale>
      <UILanguage>$Locale</UILanguage>
      <UserLocale>$Locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <UserAccounts>
        <AdministratorPassword>
          <Value>$AdminPassword</Value>
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
"@
  if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $OutputPath -Value $xml -Encoding UTF8
    return $OutputPath
  }
  return $xml
}

function New-ApexNestedVM {
  <#
  .SYNOPSIS Create a Generation 2 nested VM from a base VHDX (differencing disk).
  .DESCRIPTION
    Creates a Gen2 VM with a differencing disk off the converted base VHDX, static
    memory, the requested vCPU count, Secure Boot (Microsoft UEFI CA for OS that
    needs it), a TPM (key protector + Enable-VMTPM), and an IMDS deny ACL on the
    nested adapter (OWNED-SCOPE M4: stops a nested node from grabbing the Azure
    HOST's managed identity at 169.254.169.254). Optionally injects an unattend.xml.
    With -BootFromIso, attaches the ISO as the first boot device instead of using a
    pre-applied base (the proven SFF fallback path).
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [string]$BaseVhdxPath,
    [Parameter(Mandatory)] [string]$VmDiffDiskDir,
    [Parameter(Mandatory)] [string]$SwitchName,
    [int]$MemoryMB = 4096,
    [int]$CpuCount = 4,
    [string]$UnattendPath,
    [string]$ImdsAddress = '169.254.169.254',
    [switch]$EnableTpm,
    [switch]$BootFromIso,
    [string]$IsoPath
  )
  # Idempotency: remove any prior instance + its differencing disk.
  $existing = Get-VM -Name $VmName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-ApexLog "Removing existing VM '$VmName' for a clean rebuild." -Level WARN
    if ($existing.State -ne 'Off') { Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue }
    Remove-VM -Name $VmName -Force -ErrorAction SilentlyContinue
  }
  if (-not (Test-Path $VmDiffDiskDir)) { New-Item -ItemType Directory -Force -Path $VmDiffDiskDir | Out-Null }
  $diff = Join-Path $VmDiffDiskDir "$VmName.vhdx"
  if (Test-Path $diff) { Remove-Item $diff -Force -ErrorAction SilentlyContinue }

  if ($BootFromIso) {
    # Fallback path: empty OS disk + boot from ISO with autounattend.
    New-VHD -Path $diff -SizeBytes 127GB -Dynamic | Out-Null
  }
  else {
    Write-ApexLog "Creating differencing disk for '$VmName' off base: $BaseVhdxPath"
    New-VHD -Path $diff -ParentPath $BaseVhdxPath -Differencing | Out-Null
    if ($UnattendPath) {
      # Inject the unattend into the OS partition (Panther) of the differencing disk.
      $m = Mount-VHD -Path $diff -Passthru | Get-Disk
      try {
        $osVol = Get-Partition -DiskNumber $m.Number | Get-Volume |
          Where-Object { $_.FileSystem -eq 'NTFS' -and $_.DriveLetter } | Select-Object -First 1
        if ($osVol) {
          $panther = "$($osVol.DriveLetter):\Windows\Panther"
          New-Item -ItemType Directory -Force -Path $panther | Out-Null
          Copy-Item -Path $UnattendPath -Destination (Join-Path $panther 'unattend.xml') -Force
          Write-ApexLog "Injected unattend.xml into '$VmName' ($($osVol.DriveLetter):)."
        }
      }
      finally { Dismount-VHD -Path $diff -ErrorAction SilentlyContinue }
    }
  }

  New-VM -Name $VmName -Generation 2 -MemoryStartupBytes ($MemoryMB * 1MB) `
    -VHDPath $diff -SwitchName $SwitchName | Out-Null
  Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false
  Set-VMProcessor -VMName $VmName -Count $CpuCount -ExposeVirtualizationExtensions $true

  if ($EnableTpm) {
    # Secure Boot on with the Microsoft UEFI CA template (needed by some OS images);
    # a key protector is required before Enable-VMTPM.
    Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
    Set-VMKeyProtector -VMName $VmName -NewLocalKeyProtector
    Enable-VMTPM -VMName $VmName
  }

  Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue

  if ($BootFromIso) {
    if (-not $IsoPath) { throw 'BootFromIso requires -IsoPath.' }
    $dvd = Add-VMDvdDrive -VMName $VmName -Path $IsoPath -Passthru
    Set-VMFirmware -VMName $VmName -FirstBootDevice $dvd
  }

  # OWNED-SCOPE M4: deny the Azure-VM IMDS endpoint on the nested adapter BEFORE boot.
  $adapter = (Get-VMNetworkAdapter -VMName $VmName)[0]
  Add-VMNetworkAdapterAcl -VMNetworkAdapter $adapter -Action Deny -Direction Inbound  -RemoteIPAddress $ImdsAddress
  Add-VMNetworkAdapterAcl -VMNetworkAdapter $adapter -Action Deny -Direction Outbound -RemoteIPAddress $ImdsAddress

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
    PowerShell Direct, promotes it to a new forest, creates the deployment OU, and
    configures it as the authoritative time source (OWNED-SCOPE M5: Azure Local is
    acutely time-sensitive). The OU pre-creation that Azure Local needs is performed
    by Invoke-ApexLocalClusterDeploy against this DC.
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
    -VmDiffDiskDir $paths.VmVhdDir -SwitchName $net.SwitchName `
    -MemoryMB 4096 -CpuCount 4 -UnattendPath $unattend -ImdsAddress $net.ImdsAddress -EnableTpm | Out-Null

  Start-VM -Name $dom.DcHostName
  Wait-ApexVMReady -VmName $dom.DcHostName -Credential $LocalAdminCredential | Out-Null

  # Static IP + loopback DNS via PowerShell Direct.
  Write-ApexLog "Configuring DC static IP $($dom.DcIpAddress)/$($net.PrefixLength)."
  Invoke-Command -VMName $dom.DcHostName -Credential $LocalAdminCredential -ScriptBlock {
    param($ip, $prefix, $gw)
    $if = (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1)
    New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $if.ifIndex -ServerAddresses '127.0.0.1'
  } -ArgumentList $dom.DcIpAddress, $net.PrefixLength, $net.Gateway

  # Promote to a new forest.
  Write-ApexLog "Promoting '$($dom.DcHostName)' to forest '$($dom.Fqdn)' (a reboot follows)."
  Invoke-Command -VMName $dom.DcHostName -Credential $LocalAdminCredential -ScriptBlock {
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

  # Create the Azure Local deployment OU + configure authoritative time (M5).
  Invoke-Command -VMName $dom.DcHostName -Credential $domainCred -ScriptBlock {
    param($ouName, $ouPath)
    Import-Module ActiveDirectory
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -ErrorAction SilentlyContinue)) {
      New-ADOrganizationalUnit -Name $ouName -ProtectedFromAccidentalDeletion $false
    }
    # Authoritative NTP from the PDC emulator; do not sync from the (paused) host clock.
    w32tm /config /manualpeerlist:"time.windows.com,0x9" /syncfromflags:manual /reliable:yes /update | Out-Null
    Restart-Service w32time -ErrorAction SilentlyContinue
  } -ArgumentList $dom.OuName, $dom.OuPath

  Write-ApexLog "Domain controller '$($dom.DcHostName)' ready (forest $($dom.Fqdn), OU $($dom.OuPath))."
  return $domainCred
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
    w32tm /resync /force | Out-Null
  } -ArgumentList $DcIpAddress
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
    -VmDiffDiskDir $paths.VmVhdDir -SwitchName $net.SwitchName `
    -MemoryMB $c.NodeMemoryMB -CpuCount $c.NodeCpuCount -UnattendPath $unattend `
    -ImdsAddress $net.ImdsAddress -EnableTpm | Out-Null

  # OWNED-SCOPE M1: add two storage-intent adapters (converged on the internal
  # switch for this nested lab; real hardware uses dedicated RDMA NICs/VLANs).
  Add-VMNetworkAdapter -VMName $name -SwitchName $net.SwitchName -Name 'StorageA' -ErrorAction SilentlyContinue
  Add-VMNetworkAdapter -VMName $name -SwitchName $net.SwitchName -Name 'StorageB' -ErrorAction SilentlyContinue

  Start-VM -Name $name
  Wait-ApexVMReady -VmName $name -Credential $LocalAdminCredential | Out-Null

  Write-ApexLog "Configuring node '$name' management IP $nodeIp."
  Invoke-Command -VMName $name -Credential $LocalAdminCredential -ScriptBlock {
    param($ip, $prefix, $gw, $dns)
    $if = (Get-NetAdapter | Where-Object Status -eq 'Up' | Sort-Object ifIndex | Select-Object -First 1)
    New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $if.ifIndex -ServerAddresses $dns
  } -ArgumentList $nodeIp, $net.PrefixLength, $net.Gateway, $net.DnsServers[0]

  Set-ApexNodeTimeSync -VmName $name -Credential $LocalAdminCredential -DcIpAddress $Config.Domain.DcIpAddress

  Write-ApexLog "Node '$name' ready at $nodeIp."
  return [pscustomobject]@{ Name = $name; IpAddress = $nodeIp }
}

function Connect-ApexNodeToArc {
  <#
  .SYNOPSIS Arc-register a node and install the Azure Local deployment prerequisites.
  .DESCRIPTION
    OWNED-SCOPE C2 (the real reimplementation iceberg): this is far more than
    'azcmagent connect'. Azure Local cloud deployment requires each node to be:
      1. An Arc-enabled server (azcmagent connect), AND
      2. Carrying the mandatory deployment extensions:
         Microsoft.AzureStackHCI/EdgeDevice + the LifecycleManager,
         DeviceManagement (ADHS), and TelemetryAndDiagnostics agents that the
         cloud deployment orchestrator drives.
    Step 1 is implemented here. Step 2 (the bootstrap agents) is installed by the
    Azure Local deployment itself once the edge devices are registered, but any
    node-side prerequisites (e.g. enabling the required Windows features) are staged
    here. This function is intentionally explicit about that boundary so it can be
    hardened against the current Azure Local release.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$VmName,
    [Parameter(Mandatory)] [pscredential]$Credential,
    [Parameter(Mandatory)] [string]$SubscriptionId,
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$Location,
    [Parameter(Mandatory)] [string]$ArcCorrelationId
  )
  Write-ApexLog "Arc-registering node '$VmName' into $ResourceGroup ($Location)."
  Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock {
    param($subId, $rg, $tenant, $loc, $corr)

    # Stage the node-side OS prerequisites the cluster deploy expects.
    foreach ($f in @('Hyper-V', 'Failover-Clustering', 'Data-Center-Bridging', 'BitLocker', 'FS-FileServer')) {
      try { Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null } catch { }
    }

    # Install the Azure Connected Machine agent (azcmagent), then connect.
    $msi = "$env:TEMP\AzureConnectedMachineAgent.msi"
    if (-not (Get-Command azcmagent -ErrorAction SilentlyContinue)) {
      Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/AzureConnectedMachineAgent' -OutFile $msi
      Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msi`" /qn /norestart"
    }
    $azcm = Join-Path $env:ProgramW6432 'AzureConnectedMachineAgent\azcmagent.exe'
    if (-not (Test-Path $azcm)) { $azcm = 'azcmagent' }

    # Managed-identity flow: the node connects using the deployment's context. For a
    # nested lab the host's MI token is brokered in; in production the cloud
    # deployment performs the Arc onboarding with its own credential.
    & $azcm connect `
      --subscription-id $subId `
      --resource-group $rg `
      --tenant-id $tenant `
      --location $loc `
      --correlation-id $corr `
      --cloud AzureCloud 2>&1 | Out-String | Write-Output
  } -ArgumentList $SubscriptionId, $ResourceGroup, $TenantId, $Location, $ArcCorrelationId

  Write-ApexLog "Node '$VmName' Arc onboarding attempted."
}

#endregion

#region ---------------------------------------------------------------- Cluster

function Invoke-ApexLocalClusterDeploy {
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

    NOTE the template parameter spelling 'AzureStackLCMAdminPasssword' (three s's)
    is intentional - it matches the vendored template exactly.
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
    [string]$TemplatePath = 'C:\ApexLocal\azlocal.json'
  )
  if (-not (Test-Path $TemplatePath)) { throw "Cluster template not found: $TemplatePath" }
  $c = $Config.Cluster
  $dom = $Config.Domain

  # --- physicalNodesSettings: { name, ipv4Address } per node ---
  $physicalNodes = @($Nodes | ForEach-Object {
      @{ name = $_.Name; ipv4Address = $_.IpAddress }
    })

  # --- intentList: converged management/compute + storage (nested lab) ---
  $intentList = @(
    @{
      name                               = 'Compute_Management'
      trafficType                        = @('Management', 'Compute')
      adapter                            = @('FABRIC')
      overrideVirtualSwitchConfiguration = $false
      virtualSwitchConfigurationOverrides = @{ enableIov = ''; loadBalancingAlgorithm = '' }
      overrideQosPolicy                  = $false
      qosPolicyOverrides                 = @{ priorityValue8021Action_Cluster = '7'; priorityValue8021Action_SMB = '3'; bandwidthPercentage_SMB = '50' }
      overrideAdapterProperty            = $false
      adapterPropertyOverrides           = @{ jumboPacket = '9014'; networkDirect = 'Disabled'; networkDirectTechnology = '' }
    },
    @{
      name                               = 'Storage'
      trafficType                        = @('Storage')
      adapter                            = @('StorageA', 'StorageB')
      overrideVirtualSwitchConfiguration = $false
      virtualSwitchConfigurationOverrides = @{ enableIov = ''; loadBalancingAlgorithm = '' }
      overrideQosPolicy                  = $false
      qosPolicyOverrides                 = @{ priorityValue8021Action_Cluster = '7'; priorityValue8021Action_SMB = '3'; bandwidthPercentage_SMB = '50' }
      overrideAdapterProperty            = $false
      adapterPropertyOverrides           = @{ jumboPacket = '9014'; networkDirect = 'Disabled'; networkDirectTechnology = '' }
    }
  )

  # --- storageNetworkList: StorageA/StorageB with the configured VLANs ---
  $storageNetworkList = @(
    @{ name = 'StorageA'; networkAdapterName = 'StorageA'; vlanId = "$($c.StorageVlanA)" },
    @{ name = 'StorageB'; networkAdapterName = 'StorageB'; vlanId = "$($c.StorageVlanB)" }
  )

  # --- generated, globally-unique resource names ---
  $suffix = ([guid]::NewGuid().ToString('N')).Substring(0, 6).ToLower()
  $keyVaultName = "apxkv$suffix"
  $witnessSa = "apxwit$suffix"
  $diagSa = "apxdiag$suffix"

  $common = @{
    ResourceGroupName                = $ResourceGroup
    TemplateFile                     = $TemplatePath
    clusterName                      = $ClusterName
    location                         = $InstanceLocation
    tenantId                         = [Environment]::GetEnvironmentVariable('APEX_TenantId', 'Machine')
    hciResourceProviderObjectID      = $HciResourceProviderObjectId
    arcNodeResourceIds               = $ArcNodeResourceIds
    domainFqdn                       = $dom.Fqdn
    adouPath                         = $dom.OuPath
    namingPrefix                     = 'apexloc'
    localAdminUserName               = $LocalAdminCredential.UserName
    localAdminPassword               = $LocalAdminCredential.Password
    AzureStackLCMAdminUsername       = $DomainAdminCredential.UserName
    AzureStackLCMAdminPasssword      = $DomainAdminCredential.Password   # template spelling (3 s)
    keyVaultName                     = $keyVaultName
    clusterWitnessStorageAccountName = $witnessSa
    diagnosticStorageAccountName     = $diagSa
    physicalNodesSettings            = $physicalNodes
    intentList                       = $intentList
    storageNetworkList               = $storageNetworkList
    networkingType                   = 'switchedMultiServerDeployment'
    storageConnectivitySwitchless    = $false
    enableStorageAutoIp              = $true
    customLocation                   = "$ClusterName-cl"
    startingIPAddress                = $c.StartingIp
    endingIPAddress                  = $c.EndingIp
    subnetMask                       = $c.SubnetMask
    defaultGateway                   = $c.DefaultGateway
    dnsServers                       = @($dom.DcIpAddress)
    witnessType                      = $c.WitnessType
    securityLevel                    = 'Recommended'
    configurationMode                = 'Express'
  }

  Write-ApexLog "Validating cluster '$ClusterName' (deploymentMode=Validate)..."
  New-AzResourceGroupDeployment @common -deploymentMode 'Validate' `
    -Name "apexlocal-validate-$((Get-Date).ToString('yyyyMMddHHmmss'))" -Verbose -ErrorAction Stop | Out-Null
  Write-ApexLog 'Validation succeeded.'

  Write-ApexLog "Deploying cluster '$ClusterName' (deploymentMode=Deploy). This takes ~2.5-3 hours..."
  New-AzResourceGroupDeployment @common -deploymentMode 'Deploy' `
    -Name "apexlocal-deploy-$((Get-Date).ToString('yyyyMMddHHmmss'))" -Verbose -ErrorAction Stop | Out-Null
  Write-ApexLog "Cluster deployment submitted for '$ClusterName'."
}

#endregion

Export-ModuleMember -Function @(
  'Get-ApexConfig', 'Write-ApexLog', 'Connect-ApexAzure', 'Set-ApexProgress', 'Send-ApexLogsToStorage',
  'Wait-ApexStagedIso', 'Get-ApexStagedIso', 'Convert-ApexIsoToVhdx',
  'New-ApexHostSwitch',
  'New-ApexUnattendXml', 'New-ApexNestedVM', 'Wait-ApexVMReady', 'New-ApexDomainController',
  'New-ApexLocalNode', 'Connect-ApexNodeToArc', 'Set-ApexNodeTimeSync',
  'Invoke-ApexLocalClusterDeploy'
)
