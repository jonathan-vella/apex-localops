#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - build, configure, and boot the nested Azure Local SFF test VM.

.DESCRIPTION
  Creates a Generation 2 Hyper-V VM that satisfies, by construction, the Microsoft
  Learn "Review your VM setup" success gate:
      * Generation 2
      * TPM enabled
      * Secure Boot disabled
      * >= 4 virtual processors
      * 16000 MB startup memory, 256 GB VHD, attached to HV-Internal-NAT
  It applies the mandatory Azure-VM IMDS deny ACL (169.254.169.254) before first boot,
  boots the ROE Maintenance OS ISO, captures the serial console to a log, and waits for
  "ROE setup completed successfully". Progress is surfaced via the SffProgress tag.
#>
param(
  [string]$IsoPath,
  [string]$NestedVmName,
  [int]$MemoryStartupMB,
  [int]$CpuCount,
  [int]$DiskGB,
  [string]$SwitchName,
  [int]$RoeTimeoutMinutes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$rootDir = 'C:\LocalSFF'
. (Join-Path $rootDir 'Sff-Common.ps1')
$cfg = Get-SffConfig -ConfigPath (Join-Path $rootDir 'SffConfig.psd1')
Start-Transcript -Path (Join-Path $cfg.Paths.LogsDir 'New-SffTestVm.log') -Append

# --- Resolve parameters (explicit args win, else env vars, else config defaults) ---
$resourceGroup = [Environment]::GetEnvironmentVariable('SFF_ResourceGroup', 'Machine')
if (-not $NestedVmName) { $NestedVmName = [Environment]::GetEnvironmentVariable('SFF_NestedVmName', 'Machine'); if (-not $NestedVmName) { $NestedVmName = $cfg.NestedVm.Name } }
if (-not $MemoryStartupMB) { $MemoryStartupMB = [int]([Environment]::GetEnvironmentVariable('SFF_NestedVmMemoryMB', 'Machine')); if (-not $MemoryStartupMB) { $MemoryStartupMB = $cfg.NestedVm.MemoryMB } }
if (-not $CpuCount) { $CpuCount = [int]([Environment]::GetEnvironmentVariable('SFF_NestedVmCpuCount', 'Machine')); if (-not $CpuCount) { $CpuCount = $cfg.NestedVm.CpuCount } }
if (-not $DiskGB) { $DiskGB = [int]([Environment]::GetEnvironmentVariable('SFF_NestedVmDiskGB', 'Machine')); if (-not $DiskGB) { $DiskGB = $cfg.NestedVm.DiskGB } }
if (-not $SwitchName) { $SwitchName = [Environment]::GetEnvironmentVariable('SFF_HvSwitchName', 'Machine'); if (-not $SwitchName) { $SwitchName = $cfg.Network.SwitchName } }
if (-not $RoeTimeoutMinutes) { $RoeTimeoutMinutes = $cfg.NestedVm.RoeTimeoutMinutes }
if ($CpuCount -lt 4) { $CpuCount = 4 }   # enforce the gate minimum

$vhdPath = Join-Path $cfg.Paths.VhdDir "$NestedVmName.vhdx"
$serialLog = Join-Path $cfg.Paths.LogsDir "$NestedVmName-serial.log"
$pipeName = "$NestedVmName-com1"
$imds = $cfg.NestedVm.ImdsAddress
$roePattern = $cfg.NestedVm.RoeSuccessPattern

if (-not (Test-Path $IsoPath)) { throw "ROE ISO not found at: $IsoPath" }

Write-SffLog "Building nested SFF test VM '$NestedVmName' (Gen2, ${MemoryStartupMB}MB, ${CpuCount}vCPU, ${DiskGB}GB, switch '$SwitchName')."

# --- Idempotency: remove any prior instance of this VM ---
$existing = Get-VM -Name $NestedVmName -ErrorAction SilentlyContinue
if ($existing) {
  Write-SffLog "Removing existing VM '$NestedVmName' for a clean rebuild."
  if ($existing.State -ne 'Off') { Stop-VM -Name $NestedVmName -TurnOff -Force -ErrorAction SilentlyContinue }
  Remove-VM -Name $NestedVmName -Force -ErrorAction SilentlyContinue
}
if (Test-Path $vhdPath) { Remove-Item -Path $vhdPath -Force -ErrorAction SilentlyContinue }

# --- Create the OS VHDX and the Generation 2 VM ---
New-Item -ItemType Directory -Force -Path (Split-Path $vhdPath) | Out-Null
New-VHD -Path $vhdPath -SizeBytes ($DiskGB * 1GB) -Dynamic | Out-Null
New-VM -Name $NestedVmName -Generation 2 `
  -MemoryStartupBytes ($MemoryStartupMB * 1MB) `
  -VHDPath $vhdPath -SwitchName $SwitchName | Out-Null

# --- Static memory + >= 4 vCPU ---
Set-VMMemory -VMName $NestedVmName -DynamicMemoryEnabled $false
Set-VMProcessor -VMName $NestedVmName -Count $CpuCount

# --- Secure Boot OFF ---
Set-VMFirmware -VMName $NestedVmName -EnableSecureBoot Off

# --- TPM ON (a key protector is required before Enable-VMTPM) ---
Set-VMKeyProtector -VMName $NestedVmName -NewLocalKeyProtector
Enable-VMTPM -VMName $NestedVmName

# --- Attach the ROE ISO and make it the first boot device ---
$dvd = Add-VMDvdDrive -VMName $NestedVmName -Path $IsoPath -Passthru
Set-VMFirmware -VMName $NestedVmName -FirstBootDevice $dvd

# --- Disable automatic checkpoints (they interfere with the ROE boot) ---
Set-VM -Name $NestedVmName -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue

# --- Map COM1 to a named pipe so we can read the serial console ---
Set-VMComPort -VMName $NestedVmName -Number 1 -Path "\\.\pipe\$pipeName"

# --- Azure-VM IMDS workaround: deny 169.254.169.254 BEFORE first boot ---
$adapter = (Get-VMNetworkAdapter -VMName $NestedVmName)[0]
Add-VMNetworkAdapterAcl -VMNetworkAdapter $adapter -Action Deny -Direction Inbound  -RemoteIPAddress $imds
Add-VMNetworkAdapterAcl -VMNetworkAdapter $adapter -Action Deny -Direction Outbound -RemoteIPAddress $imds
Write-SffLog "Applied IMDS deny ACL ($imds) on the nested adapter."

# --- Verify the four-point success gate before boot ---
$gen = (Get-VM -Name $NestedVmName).Generation
$sb = (Get-VMFirmware -VMName $NestedVmName).SecureBoot
$tpm = (Get-VMSecurity  -VMName $NestedVmName).TpmEnabled
$cpu = (Get-VMProcessor -VMName $NestedVmName).Count
Write-SffLog "Gate check => Generation=$gen  SecureBoot=$sb  TpmEnabled=$tpm  vCPU=$cpu"
if ($gen -ne 2 -or "$sb" -ne 'Off' -or -not $tpm -or $cpu -lt 4) {
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'Failed' -Status "Gate check failed: Gen=$gen SB=$sb TPM=$tpm vCPU=$cpu" -Config $cfg
  Stop-Transcript
  throw "Nested VM does not satisfy the SFF success gate."
}
Set-SffProgress -ResourceGroup $resourceGroup -Progress 'NestedVmCreated' -Status "Gen2/TPM/SBoff/${cpu}vCPU verified" -Config $cfg

# --- Start a background serial-console reader (named-pipe client -> log file) ---
if (Test-Path $serialLog) { Remove-Item $serialLog -Force -ErrorAction SilentlyContinue }
$readerJob = Start-Job -ScriptBlock {
  param($pipe, $log)
  try {
    $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipe, [System.IO.Pipes.PipeDirection]::In)
    $client.Connect(120000)
    $reader = New-Object System.IO.StreamReader($client)
    while (-not $reader.EndOfStream) {
      $line = $reader.ReadLine()
      if ($null -ne $line) { Add-Content -Path $log -Value $line }
    }
  }
  catch {
    Add-Content -Path $log -Value "[serial-reader] $($_.Exception.Message)"
  }
} -ArgumentList $pipeName, $serialLog

# --- Boot and wait for the ROE success signal ---
Start-VM -Name $NestedVmName
Set-SffProgress -ResourceGroup $resourceGroup -Progress 'RoeBooting' -Status 'Nested VM started; awaiting ROE' -Config $cfg
Write-SffLog "Nested VM started. Waiting up to $RoeTimeoutMinutes min for: '$roePattern'."

$deadline = (Get-Date).AddMinutes($RoeTimeoutMinutes)
$roeOk = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 20
  if (Test-Path $serialLog) {
    if (Select-String -Path $serialLog -Pattern $roePattern -Quiet -ErrorAction SilentlyContinue) {
      $roeOk = $true
      break
    }
  }
}

Stop-Job $readerJob -ErrorAction SilentlyContinue | Out-Null
Remove-Job $readerJob -Force -ErrorAction SilentlyContinue | Out-Null

if ($roeOk) {
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'RoeSucceeded' -Status 'ROE setup completed successfully' -Config $cfg
  Write-SffLog "SUCCESS: ROE reported '$roePattern'."
  $vmIp = ''
  try {
    $vmIp = (Get-VMNetworkAdapter -VMName $NestedVmName).IPAddresses | Where-Object { $_ -match '^\d+\.' } | Select-Object -First 1
  }
  catch { }

  # --- Zero-touch: try to extract the ownership voucher over SSH and store it in
  #     Key Vault automatically (replaces the GUI Configurator step). Best-effort:
  #     on any failure we fall back to the guided path below. ---
  $voucherStored = $false
  try {
    $voucherScript = Join-Path $cfg.Paths.RootDir 'Get-OwnershipVoucher-Ssh.ps1'
    if (Test-Path $voucherScript) {
      Write-SffLog 'Attempting headless ownership-voucher extraction over SSH...'
      $voucherStored = [bool](& $voucherScript -NestedVmName $NestedVmName -NestedVmIp $vmIp -ResourceGroup $resourceGroup)
    }
  }
  catch {
    Write-SffLog "Automatic voucher extraction errored: $($_.Exception.Message)" -Level WARN
  }

  if ($voucherStored) {
    $next = @"
Nested SFF test VM '$NestedVmName' booted the Maintenance OS AND the ownership voucher
was extracted automatically and stored in Key Vault (SffProgress=VoucherStored).
Next: provision the machine in Azure from the voucher, then deploy AKS:
  scripts/provision-machine.sh   (auto if the preview CLI is present, else guided)
  scripts/resolve-aks-inputs.sh && scripts/deploy-aks-baremetal.sh
See docs/sff-zero-touch.md for the fully chained scripts/deploy-all.sh path.
"@
  }
  else {
    $next = @"
Nested SFF test VM '$NestedVmName' booted the Maintenance OS successfully.
Automatic voucher extraction was not possible; download it manually:
  1. Open the Configurator App on this host.
  2. Enter the nested VM IP$(if ($vmIp) { " ($vmIp)" } else { ' (see Hyper-V console)' }), user 'edgeuser', password 'Password1'.
  3. Select 'Download Ownership Voucher' and save the .pem.
  4. Run:  C:\LocalSFF\Save-OwnershipVoucher.ps1 -Path <voucher>.pem
See docs/sff-runbook.md for portal machine provisioning.
"@
  }
  Set-Content -Path (Join-Path $cfg.Paths.LogsDir 'NEXT-STEPS.txt') -Value $next
  Write-SffLog $next
}
else {
  Set-SffProgress -ResourceGroup $resourceGroup -Progress 'RoeTimeout' -Status "No '$roePattern' within $RoeTimeoutMinutes min; verify via Hyper-V console / Configurator App" -Config $cfg
  Write-SffLog "ROE success string not observed within $RoeTimeoutMinutes min. The VM may still be healthy - verify via the Hyper-V console; serial log: $serialLog" -Level WARN
}

Stop-Transcript
