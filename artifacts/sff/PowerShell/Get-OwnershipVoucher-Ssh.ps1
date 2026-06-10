#requires -Version 5.1
<#
.SYNOPSIS
  apex-localops - headless extraction of the SFF ownership voucher over SSH.

.DESCRIPTION
  Runs ON THE HOST (which has line-of-sight to the nested ROE VM on the internal
  HV-Internal-NAT switch). Replaces the GUI Configurator App step: it discovers the
  nested VM's IP, connects over SSH as the maintenance-OS account (edgeuser/Password1),
  copies the ownership voucher .pem from /var/staging/export/vouchers/<serial>/<serial>.pem,
  and stores it in Key Vault via Save-OwnershipVoucher.ps1. Tags SffProgress=VoucherStored.

  Best-effort by design: any failure logs a warning and returns $false so the caller can
  fall back to the guided Configurator path. The maintenance-OS credentials are the fixed
  Microsoft eval credentials, reachable only on the host's isolated 192.168.200.0/24 switch.

.OUTPUTS
  [bool] $true if the voucher was extracted and stored, else $false.
#>
param(
  [string]$NestedVmName,
  [string]$NestedVmIp,
  [string]$EdgeUser = 'edgeuser',
  [string]$EdgePassword = 'Password1',
  [string]$RemoteVoucherGlob = '/var/staging/export/vouchers/*/*.pem',
  [string]$KeyVaultName,
  [string]$ResourceGroup,
  [int]$DiscoverTimeoutMinutes = 10
)

$ErrorActionPreference = 'Stop'

$rootDir = 'C:\LocalSFF'
. (Join-Path $rootDir 'Sff-Common.ps1')
$cfg = Get-SffConfig -ConfigPath (Join-Path $rootDir 'SffConfig.psd1')

if (-not $NestedVmName)   { $NestedVmName = [Environment]::GetEnvironmentVariable('SFF_NestedVmName', 'Machine'); if (-not $NestedVmName) { $NestedVmName = $cfg.NestedVm.Name } }
if (-not $KeyVaultName)   { $KeyVaultName = [Environment]::GetEnvironmentVariable('SFF_KeyVaultName', 'Machine') }
if (-not $ResourceGroup)  { $ResourceGroup = [Environment]::GetEnvironmentVariable('SFF_ResourceGroup', 'Machine') }

# --- Resolve the nested VM IP (VM integration first, then the DHCP lease) ---
function Resolve-NestedIp {
  param([string]$VmName, [string]$SubnetPrefix)
  # 1) Hyper-V guest IP (requires guest integration; may be absent on ROE).
  try {
    $ip = (Get-VMNetworkAdapter -VMName $VmName -ErrorAction Stop).IPAddresses |
      Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
    if ($ip) { return $ip }
  } catch { }
  # 2) DHCP lease on the host's WinNAT scope, matched by the VM's MAC.
  try {
    $scopeId = ($SubnetPrefix -split '/')[0]
    $mac = ((Get-VMNetworkAdapter -VMName $VmName -ErrorAction Stop).MacAddress) -replace '[^0-9A-Fa-f]', ''
    $lease = Get-DhcpServerv4Lease -ScopeId $scopeId -ErrorAction Stop |
      Where-Object { ($_.ClientId -replace '[^0-9A-Fa-f]', '') -ieq $mac -and $_.IPAddress } |
      Select-Object -First 1
    if ($lease) { return $lease.IPAddress.IPAddressToString }
  } catch { }
  return $null
}

if (-not $NestedVmIp) {
  $deadline = (Get-Date).AddMinutes($DiscoverTimeoutMinutes)
  while (-not $NestedVmIp -and (Get-Date) -lt $deadline) {
    $NestedVmIp = Resolve-NestedIp -VmName $NestedVmName -SubnetPrefix $cfg.Network.SubnetPrefix
    if (-not $NestedVmIp) { Start-Sleep -Seconds 20 }
  }
}
if (-not $NestedVmIp) {
  Write-SffLog "Could not discover the nested VM IP; falling back to the guided voucher path." -Level WARN
  return $false
}
Write-SffLog "Nested VM IP resolved: $NestedVmIp"

# --- Ensure the Posh-SSH module (headless password-auth SSH on Windows) ---
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
  try {
    Write-SffLog 'Installing Posh-SSH module for headless SSH voucher extraction.'
    Install-Module -Name Posh-SSH -Scope AllUsers -Force -AllowClobber
  } catch {
    Write-SffLog "Posh-SSH install failed ($($_.Exception.Message)); falling back to the guided voucher path." -Level WARN
    return $false
  }
}
Import-Module Posh-SSH -ErrorAction Stop

# --- Connect and pull the voucher as base64 (single command; avoids SCP subsystem quirks) ---
$securePw = ConvertTo-SecureString $EdgePassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($EdgeUser, $securePw)
$session = $null
try {
  $session = New-SSHSession -ComputerName $NestedVmIp -Credential $cred -AcceptKey -ConnectionTimeout 30 -ErrorAction Stop
  $remoteCmd = "f=`$(ls $RemoteVoucherGlob 2>/dev/null | head -1); if [ -n `"`$f`" ]; then base64 -w0 `"`$f`"; else echo NO_VOUCHER; fi"
  $result = Invoke-SSHCommand -SSHSession $session -Command $remoteCmd -TimeOut 60
  $payload = ($result.Output -join '').Trim()
  if (-not $payload -or $payload -eq 'NO_VOUCHER') {
    Write-SffLog "No voucher found at $RemoteVoucherGlob on the nested VM yet; falling back to the guided path." -Level WARN
    return $false
  }
  $localPem = Join-Path $cfg.Paths.RootDir 'ownership-voucher.pem'
  [System.IO.File]::WriteAllBytes($localPem, [System.Convert]::FromBase64String($payload))
  Write-SffLog "Ownership voucher copied to $localPem ($((Get-Item $localPem).Length) bytes)."
} catch {
  Write-SffLog "SSH voucher extraction failed ($($_.Exception.Message)); falling back to the guided path." -Level WARN
  return $false
} finally {
  if ($session) { Remove-SSHSession -SSHSession $session | Out-Null }
}

# --- Store it in Key Vault via the existing helper ---
try {
  & (Join-Path $rootDir 'Save-OwnershipVoucher.ps1') -Path $localPem -KeyVaultName $KeyVaultName -ResourceGroup $ResourceGroup
  # The local copy is no longer needed once it's safely in Key Vault.
  Remove-Item $localPem -Force -ErrorAction SilentlyContinue
  return $true
} catch {
  Write-SffLog "Storing the voucher in Key Vault failed: $($_.Exception.Message)" -Level WARN
  return $false
}
