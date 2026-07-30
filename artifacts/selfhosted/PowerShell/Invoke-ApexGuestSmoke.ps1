#requires -Version 5.1
<#
.SYNOPSIS
  In-guest smoke gate: build one throwaway nested guest and exercise the guest-facing
  contract before any paid full deployment.
.DESCRIPTION
  Static gates (Bicep what-if, PSScriptAnalyzer, source-contract Pester) cannot observe a
  freshly applied offline Windows image. A whole class of defects is therefore invisible to
  them and has historically surfaced only during billed multi-hour deployments:
    - an unlettered OS partition that unattend injection cannot reach,
    - the generic UEFI Secure Boot template refusing to boot the Windows boot manager,
    - a nested guest with no registered PSGallery for module acquisition,
    - cold Active Directory Web Services (ADWS) after a domain-controller promotion.

  This gate builds ONE throwaway nested guest from the already-converted Windows Server base
  VHDX on V: and drives it through the real guest-facing code path in four checks:
    1. GuestProvisioned  - New-ApexNestedVM injects unattend.xml into the unlettered OS
                           partition (temporary drive-letter allocation), applies the Windows
                           Secure Boot template + vTPM, and denies the IMDS endpoint.
    2. SecureBootBoot    - Start-VM + Wait-ApexVMReady prove the image boots under the Windows
                           Secure Boot template and PowerShell Direct is reachable.
    3. ModuleSideLoad    - Install-ApexGuestModule side-loads a pinned module from the host into
                           the guest with no gallery access inside the guest.
    4. AdPromotionReady  - the guest is promoted to a throwaway forest and ADWS/DNS/NTDS are
                           verified Running, exercising the cold-ADWS failure mode.

  Runs on the cluster host after the base images exist (the BaseImages stage). It reuses the
  existing internal Hyper-V switch, needs no Azure egress, completes in minutes, and always
  removes the throwaway guest. Any failed check exits non-zero and blocks promotion to a full
  run. It writes a redacted guest-smoke-summary.json (check names, status, durations) for the
  release evidence; it records no secrets.
.PARAMETER AdminPassword
  Lab administrator password for the throwaway guest. When omitted, the machine-scoped
  APEX_AdminPasswordB64 value set by Bootstrap.ps1 is used. Supplied as an encrypted protected
  parameter under Azure Managed Run Command; the plaintext is cleared before exit.
.PARAMETER KeepGuest
  Leave the throwaway guest in place for manual inspection instead of removing it. For debugging
  a failed gate only; the default removes the guest.
.EXAMPLE
  ./Invoke-ApexGuestSmoke.ps1
  Runs the gate using the host's staged credential and tears the guest down.
.EXAMPLE
  ./Invoke-ApexGuestSmoke.ps1 -AdminPassword '<lab-password>' -KeepGuest
  Runs the gate with an explicit credential and keeps the guest for inspection.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
  'PSAvoidUsingConvertToSecureStringWithPlainText',
  '',
  Justification = 'The lab password arrives as a protected Managed Run Command parameter or a machine env value; the gate converts it only for PowerShell Direct into the throwaway guest and clears the plaintext before exit.'
)]
[CmdletBinding()]
param(
  [string]$AdminPassword,
  [switch]$KeepGuest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$rootDir = 'C:\ApexLocal'
$logsDir = Join-Path $rootDir 'Logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
Start-Transcript -Path (Join-Path $logsDir 'Invoke-ApexGuestSmoke.log') -Append | Out-Null

Import-Module (Join-Path $rootDir 'ApexLocalOps\ApexLocalOps.psd1') -Force
$cfg = Get-ApexConfig -ConfigPath (Join-Path $rootDir 'ApexLocal-Config.psd1')
$moduleVersions = Import-PowerShellDataFile -Path (Join-Path $rootDir 'ModuleVersions.psd1')

# The gate builds a VM on this host, so it must not run alongside a real build or recovery.
$buildMutex = New-Object System.Threading.Mutex($false, 'Global\ApexLocalBuild')
if (-not $buildMutex.WaitOne(0)) {
  $buildMutex.Dispose()
  Write-Error 'An Apex Local build or recovery is already running on this host.'
  Stop-Transcript | Out-Null
  exit 2
}

function Invoke-ApexSmokeCheck {
  <#
  .SYNOPSIS Run one named smoke check, record its outcome and duration, and re-throw on failure.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [scriptblock]$Action
  )
  Write-ApexLog "Smoke check '$Name' started."
  $startedAt = Get-Date
  try {
    & $Action
  }
  catch {
    $script:smokeResults += [pscustomobject]@{
      Check           = $Name
      Status          = 'Failed'
      DurationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
      Detail          = $_.Exception.Message
    }
    Write-ApexLog "Smoke check '$Name' FAILED: $($_.Exception.Message)" -Level ERROR
    throw
  }
  $script:smokeResults += [pscustomobject]@{
    Check           = $Name
    Status          = 'Passed'
    DurationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
    Detail          = ''
  }
  Write-ApexLog "Smoke check '$Name' passed."
}

# Throwaway identity kept clear of the real build's names and IP map: 192.168.1.240 sits
# outside the DC/node/gateway/cluster-pool addresses declared in ApexLocal-Config.psd1.
$guestName = 'apex-smoke'
$smokeDomainFqdn = 'apexsmoke.local'
$smokeDomainNetBios = 'APEXSMOKE'
$smokeGuestIp = '192.168.1.240'

$wsBaseVhdx = Join-Path $cfg.Paths.BaseVhdDir 'windowsserver-base.vhdx'
$script:smokeResults = @()
$script:unattendPath = $null
$script:smokeSession = $null
$securePw = $null
$gateFailed = $false

try {
  # Fail here, in seconds, rather than after minutes of nested VM construction.
  if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V is not installed on this host; run the HostFabric stage first.'
  }
  if (-not (Get-VMSwitch -Name $cfg.Network.SwitchName -ErrorAction SilentlyContinue)) {
    throw "Internal switch '$($cfg.Network.SwitchName)' is missing; run the HostFabric stage first."
  }
  if (-not (Test-Path -LiteralPath $wsBaseVhdx)) {
    throw "Windows Server base VHDX not found at '$wsBaseVhdx'; run the BaseImages stage first."
  }

  if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    $adminPwB64 = [Environment]::GetEnvironmentVariable('APEX_AdminPasswordB64', 'Machine')
    if ([string]::IsNullOrWhiteSpace($adminPwB64)) {
      throw 'No -AdminPassword supplied and APEX_AdminPasswordB64 is not set on this host.'
    }
    $AdminPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($adminPwB64))
  }
  $securePw = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
  $localAdminCred = New-Object System.Management.Automation.PSCredential('Administrator', $securePw)

  Invoke-ApexSmokeCheck -Name 'GuestProvisioned' -Action {
    $script:unattendPath = New-ApexUnattendXml -ComputerName $guestName `
      -AdminPassword $AdminPassword `
      -OutputPath (Join-Path $cfg.Paths.AnswerDir "$guestName-unattend.xml")
    New-ApexNestedVM -VmName $guestName -BaseVhdxPath $wsBaseVhdx `
      -VmDiffDiskDir $cfg.Paths.VmVhdDir -VmConfigDir $cfg.Paths.VmDir `
      -SwitchName $cfg.Network.SwitchName -MemoryMB 4096 -CpuCount 4 `
      -UnattendPath $script:unattendPath -ImdsAddress $cfg.Network.ImdsAddress -EnableTpm | Out-Null
  }

  Invoke-ApexSmokeCheck -Name 'SecureBootBoot' -Action {
    Start-VM -Name $guestName
    Wait-ApexVMReady -VmName $guestName -Credential $localAdminCred -TimeoutMinutes 30 | Out-Null
  }

  Invoke-ApexSmokeCheck -Name 'ModuleSideLoad' -Action {
    $script:smokeSession = New-PSSession -VMName $guestName -Credential $localAdminCred -ErrorAction Stop
    Install-ApexGuestModule -Name 'Az.Accounts' -RequiredVersion $moduleVersions.AzAccounts `
      -Session $script:smokeSession -StagingPath (Join-Path $rootDir 'GuestModules')
    Remove-PSSession -Session $script:smokeSession -ErrorAction SilentlyContinue
    $script:smokeSession = $null
  }

  Invoke-ApexSmokeCheck -Name 'AdPromotionReady' -Action {
    # Static IP + loopback DNS so the isolated guest promotes without APIPA or an external
    # resolver; no gateway is set because this gate needs no egress.
    Invoke-Command -VMName $guestName -Credential $localAdminCred -ScriptBlock {
      param($ip, $prefix)
      $netAdapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
      New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $ip -PrefixLength $prefix `
        -ErrorAction SilentlyContinue | Out-Null
      Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -ServerAddresses '127.0.0.1'
    } -ArgumentList $smokeGuestIp, $cfg.Network.PrefixLength

    Invoke-Command -VMName $guestName -Credential $localAdminCred -ScriptBlock {
      param($fqdn, $netbios, $safePwd)
      Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
      Import-Module ADDSDeployment
      Install-ADDSForest -DomainName $fqdn -DomainNetbiosName $netbios `
        -SafeModeAdministratorPassword $safePwd -InstallDns -Force -NoRebootOnCompletion:$false
    } -ArgumentList $smokeDomainFqdn, $smokeDomainNetBios, $securePw

    # Reconnect as the new domain admin and confirm the promotion produced a live directory:
    # cold ADWS/NTDS/DNS is the exact defect this check exists to catch.
    $smokeDomainCred = New-Object System.Management.Automation.PSCredential(
      "$smokeDomainNetBios\Administrator", $securePw)
    Start-Sleep -Seconds 60
    Wait-ApexVMReady -VmName $guestName -Credential $smokeDomainCred -TimeoutMinutes 30 | Out-Null

    $readyDeadline = (Get-Date).AddMinutes(15)
    $readyError = $null
    while ((Get-Date) -lt $readyDeadline) {
      try {
        Invoke-Command -VMName $guestName -Credential $smokeDomainCred -ErrorAction Stop -ScriptBlock {
          param($fqdn)
          Import-Module ActiveDirectory -ErrorAction Stop
          $domain = Get-ADDomain -Identity $fqdn -ErrorAction Stop
          $dnsRecord = Resolve-DnsName -Name $fqdn -Server '127.0.0.1' -ErrorAction Stop
          $requiredServices = Get-Service -Name ADWS, DNS, NTDS -ErrorAction Stop
          if ($domain.DNSRoot -ne $fqdn -or -not $dnsRecord -or
            @($requiredServices | Where-Object Status -ne 'Running').Count -gt 0) {
            throw "Post-promotion AD/ADWS readiness failed for '$fqdn'."
          }
        } -ArgumentList $smokeDomainFqdn
        $readyError = $null
        break
      }
      catch {
        $readyError = $_.Exception.Message
        Start-Sleep -Seconds 20
      }
    }
    if ($readyError) {
      throw "Timed out waiting for post-promotion AD/ADWS readiness. Last error: $readyError"
    }
  }

  Write-ApexLog 'In-guest smoke gate passed all checks.'
}
catch {
  $gateFailed = $true
  Write-ApexLog "In-guest smoke gate failed: $($_.Exception.Message)" -Level ERROR
}
finally {
  if ($script:smokeSession) {
    Remove-PSSession -Session $script:smokeSession -ErrorAction SilentlyContinue
  }

  if (-not $KeepGuest) {
    $existingGuest = Get-VM -Name $guestName -ErrorAction SilentlyContinue
    if ($existingGuest) {
      if ($existingGuest.State -ne 'Off') {
        Stop-VM -Name $guestName -TurnOff -Force -ErrorAction SilentlyContinue
      }
      Remove-VM -Name $guestName -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path (Join-Path $cfg.Paths.VmVhdDir "$guestName.vhdx") -Force -ErrorAction SilentlyContinue
    if ($script:unattendPath) {
      Remove-Item -Path $script:unattendPath -Force -ErrorAction SilentlyContinue
    }
    Write-ApexLog "Removed throwaway guest '$guestName'."
  }
  else {
    Write-ApexLog "Left throwaway guest '$guestName' in place (-KeepGuest)." -Level WARN
  }

  # Redacted evidence only: check names, status, and durations. No secrets, no fabric IPs,
  # no credential material.
  $summary = [pscustomobject]@{
    Gate         = 'InGuestSmoke'
    GeneratedUtc = (Get-Date).ToUniversalTime().ToString('o')
    GuestName    = $guestName
    Passed       = (-not $gateFailed)
    Checks       = $script:smokeResults
  }
  $summaryPath = Join-Path $logsDir 'guest-smoke-summary.json'
  $summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8
  Write-ApexLog "Wrote smoke summary to '$summaryPath'."

  # Clear the in-process plaintext and secure copies of the lab credential.
  if ($securePw) { $securePw.Dispose() }
  $AdminPassword = $null
  Remove-Variable -Name AdminPassword -ErrorAction SilentlyContinue

  $buildMutex.ReleaseMutex()
  $buildMutex.Dispose()
  Stop-Transcript | Out-Null
}

if ($gateFailed) {
  exit 1
}
exit 0
