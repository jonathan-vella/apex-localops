<#
.SYNOPSIS
    AzLocalWorkloads - idempotent helpers to deploy post-cluster workloads (VMs + AVD
    session host) on the Azure Local cluster.

.DESCRIPTION
    Runs FROM THE DEV CONTAINER (or any client) with operator `az` credentials. Every
    operation is a cloud/ARM call: VM/disk/NIC/image/lnet via the `stack-hci-vm` extension
    (custom location + Arc), and in-guest steps via the Microsoft.HybridCompute
    machines/runCommands API (Invoke-ArcRunCommand) - so nothing needs to run on
    LocalBox-Client and there is no run-command-extension wedge risk.

    Every function is ADDITIVE and IDEMPOTENT: it inspects current state and skips/echoes
    when the target already exists, so the whole module is safe to re-run and never
    modifies the cluster or its infrastructure logical network.

    No secrets are stored. The VM/domain admin password is supplied by the caller, sourced
    from the LOCALBOX_ADMIN_PASSWORD (or WORKLOADS_ADMIN_PASSWORD) environment variable -
    never written to disk or committed.

    Dependencies:
      az CLI + extensions: customlocation, stack-hci-vm
      Operator context (az login) with rights on the resource group.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

function Write-Step {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('u')
    $color = switch ($Level) { 'OK' {'Green'} 'WARN' {'Yellow'} 'ERROR' {'Red'} 'SKIP' {'DarkGray'} default {'Cyan'} }
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}

function Invoke-Az {
    <# Thin wrapper: run `az ...`, return parsed JSON (or $null), never throw on non-zero
       unless -MustSucceed. Keeps callers terse and consistent. #>
    param(
        [Parameter(Mandatory)][string[]]$Args,
        [switch]$MustSucceed,
        [switch]$Raw
    )
    $out = & az @Args 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        if ($MustSucceed) { throw "az $($Args -join ' ') failed ($code): $out" }
        return $null
    }
    if ($Raw) { return ($out -join "`n") }
    $text = ($out -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return $text | ConvertFrom-Json } catch { return $text }
}

function Resolve-AdminPassword {
    <# Resolve the VM/domain admin password from the environment (never stored on disk).
       Mirrors deploy.sh's LOCALBOX_ADMIN_PASSWORD convention. #>
    param()
    foreach ($var in 'LOCALBOX_ADMIN_PASSWORD','WORKLOADS_ADMIN_PASSWORD') {
        $val = [Environment]::GetEnvironmentVariable($var)
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    }
    throw "Admin password not set. Export LOCALBOX_ADMIN_PASSWORD (or WORKLOADS_ADMIN_PASSWORD) before running."
}

function Resolve-CustomLocationId {
    param([Parameter(Mandatory)]$Config)
    $id = Invoke-Az -Args @('customlocation','show','-g',$Config.ResourceGroup,'-n',$Config.CustomLocationName,'--query','id','-o','tsv') -Raw
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Custom location '$($Config.CustomLocationName)' not found in $($Config.ResourceGroup)." }
    return $id.Trim()
}

function Invoke-ArcRunCommand {
    <# Execute a PowerShell script inside an Azure Local Arc VM via the HybridCompute
       machines/runCommands API - works from any client with ARM access (no in-guest
       agent CLI, no `az vm run-command` wedge). Synchronous: submits the runCommand,
       polls to a terminal executionState, returns combined stdout+stderr, then deletes
       the runCommand resource (cleanup). API version = latest GA (2025-01-13). #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Script,
        [int]$TimeoutSeconds = 600,
        [int]$PollSeconds = 15,
        [string]$ApiVersion = '2025-01-13'
    )
    $sub = $Config.SubscriptionId
    $rg  = $Config.ResourceGroup
    $rcName = "alw-$([guid]::NewGuid().ToString('N').Substring(0,12))"
    $idBase = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$VmName/runCommands/$rcName"
    $putUrl = "$idBase`?api-version=$ApiVersion"
    $getUrl = "$idBase`?api-version=$ApiVersion&`$expand=instanceView"
    $body = @{
        location   = $Config.Location
        properties = @{
            source           = @{ script = $Script }
            asyncExecution   = $false
            timeoutInSeconds = $TimeoutSeconds
        }
    } | ConvertTo-Json -Depth 8
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $body -Encoding utf8
    try {
        $null = Invoke-Az -MustSucceed -Args @('rest','--method','put','--url',$putUrl,'--body',"@$tmp")
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds + 180)
        $state = $null; $output = ''; $errout = ''
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $PollSeconds
            $r = Invoke-Az -Args @('rest','--method','get','--url',$getUrl)
            if (-not $r) { continue }
            $iv = $r.properties.instanceView
            $state = if ($iv) { $iv.executionState } else { $null }
            if ($state -in @('Succeeded','Failed','TimedOut','Canceled')) {
                if ($iv) { $output = ($iv.output | Out-String); $errout = ($iv.error | Out-String) }
                break
            }
            if ($r.properties.provisioningState -eq 'Failed') { break }
        }
        if ($state -ne 'Succeeded') { Write-Step "runCommand on '$VmName' executionState=$state. stderr: $($errout.Trim())" 'WARN' }
        return ("$output`n$errout").Trim()
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        $null = Invoke-Az -Args @('rest','--method','delete','--url',$putUrl)   # best-effort cleanup
    }
}

# -----------------------------------------------------------------------------
# Phase 1 - Marketplace images (idempotent)
# -----------------------------------------------------------------------------

function Ensure-MarketplaceImage {
    <# Skip if a gallery image of this name already exists (any non-Failed state);
       otherwise create from the URN. Returns the image name. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ImageName,
        [Parameter(Mandatory)][string]$Urn,
        [string]$OsType = 'Windows',
        [string]$CustomLocationId
    )
    $existing = Invoke-Az -Args @('stack-hci-vm','image','list','-g',$Config.ResourceGroup,
        '--query',"[?name=='$ImageName'].{n:name,p:properties.provisioningState}",'-o','json')
    if ($existing -and $existing.Count -gt 0) {
        $state = $existing[0].p
        if ($state -eq 'Failed') {
            Write-Step "Image '$ImageName' exists but is Failed - leaving as-is (manual cleanup recommended)." 'WARN'
        } else {
            Write-Step "Image '$ImageName' already present (state=$state) - skipping create." 'SKIP'
        }
        return $ImageName
    }
    if (-not $CustomLocationId) { $CustomLocationId = Resolve-CustomLocationId -Config $Config }
    Write-Step "Creating image '$ImageName' from URN '$Urn' (this downloads several GB into the CSV)..."
    if ($PSCmdlet.ShouldProcess($ImageName, "create marketplace image")) {
        $null = Invoke-Az -MustSucceed -Args @('stack-hci-vm','image','create',
            '-g',$Config.ResourceGroup,'--custom-location',$CustomLocationId,
            '--location',$Config.Location,'--name',$ImageName,'--os-type',$OsType,
            '--urn',$Urn)
        Write-Step "Image '$ImageName' create submitted." 'OK'
    }
    return $ImageName
}

function Wait-ImageReady {
    <# Poll a single image until provisioningState=Succeeded (or fail/timeout). #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ImageName,
        [int]$TimeoutMinutes = 120,
        [int]$PollSeconds = 60
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $img = Invoke-Az -Args @('stack-hci-vm','image','list','-g',$Config.ResourceGroup,
            '--query',"[?name=='$ImageName'].properties.provisioningState",'-o','tsv') -Raw
        $state = ($img | Out-String).Trim()
        if ($state -eq 'Succeeded') { Write-Step "Image '$ImageName' = Succeeded." 'OK'; return $true }
        if ($state -eq 'Failed')    { throw "Image '$ImageName' provisioning Failed." }
        Write-Step "Image '$ImageName' state='$state' - waiting..." 'INFO'
        Start-Sleep -Seconds $PollSeconds
    }
    throw "Timed out after $TimeoutMinutes min waiting for image '$ImageName'."
}

# -----------------------------------------------------------------------------
# Phase 2 - Logical network (idempotent; reuses the existing vlan200 lnet)
# -----------------------------------------------------------------------------

function Ensure-WorkloadLogicalNetwork {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Config, [string]$CustomLocationId)
    $ln = $Config.LogicalNetwork
    $found = Invoke-Az -Args @('stack-hci-vm','network','lnet','list','-g',$Config.ResourceGroup,
        '--query',"[?name=='$($ln.Name)'].name",'-o','tsv') -Raw
    if (-not [string]::IsNullOrWhiteSpace(($found | Out-String).Trim())) {
        Write-Step "Logical network '$($ln.Name)' already exists - skipping create." 'SKIP'
        return $ln.Name
    }
    if (-not $CustomLocationId) { $CustomLocationId = Resolve-CustomLocationId -Config $Config }
    Write-Step "Creating logical network '$($ln.Name)' (vlan $($ln.Vlan), $($ln.AddressPrefix))..."
    if ($PSCmdlet.ShouldProcess($ln.Name, "create logical network")) {
        $null = Invoke-Az -MustSucceed -Args @('stack-hci-vm','network','lnet','create',
            '-g',$Config.ResourceGroup,'--custom-location',$CustomLocationId,'--location',$Config.Location,
            '--name',$ln.Name,'--vm-switch-name',$Config.VmSwitchName,
            '--ip-allocation-method','static','--address-prefixes',$ln.AddressPrefix,
            '--gateway',$ln.Gateway,'--dns-servers',($ln.DnsServers -join ' '),'--vlan',"$($ln.Vlan)",
            '--ip-pool-start',$ln.IpPoolStart,'--ip-pool-end',$ln.IpPoolEnd)
        Write-Step "Logical network '$($ln.Name)' created." 'OK'
    }
    return $ln.Name
}

# -----------------------------------------------------------------------------
# Phase 4/5/6 - Workload VMs (idempotent)
# -----------------------------------------------------------------------------

function New-WorkloadVm {
    <# Create NIC (on the lnet) + data disks + the VM, idempotently. Returns the VM name.
       VM is created with guest agent enabled (--enable-agent) so run-command + Arc/IMDS work. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Vm,                 # one entry from $Config.Vms
        [string]$CustomLocationId,
        [string]$AdminPassword,                    # resolved by caller (not stored)
        [int]$StoragePathIndex = 0
    )
    if (-not $CustomLocationId) { $CustomLocationId = Resolve-CustomLocationId -Config $Config }
    $img = $Config.Images[$Vm.ImageKey]
    if (-not $img) { throw "VM '$($Vm.Name)': ImageKey '$($Vm.ImageKey)' not found in Config.Images." }
    $storagePathId = $Config.StoragePathIds[$StoragePathIndex % $Config.StoragePathIds.Count]
    $lnetName = $Config.LogicalNetwork.Name
    $subId = $Config.SubscriptionId
    $lnetId = "/subscriptions/$subId/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.AzureStackHCI/logicalNetworks/$lnetName"

    # Idempotency: VM already exists?
    $existingVm = Invoke-Az -Args @('stack-hci-vm','list','-g',$Config.ResourceGroup,
        '--query',"[?name=='$($Vm.Name)'].{n:name,p:provisioningState}",'-o','json')
    if ($existingVm -and $existingVm.Count -gt 0) {
        Write-Step "VM '$($Vm.Name)' already exists (state=$($existingVm[0].p)) - skipping create." 'SKIP'
        return $Vm.Name
    }

    # Password is only needed to actually create the VM; skip resolving it on a -WhatIf dry run.
    if (-not $AdminPassword -and -not $WhatIfPreference) { $AdminPassword = Resolve-AdminPassword }

    # 1) NIC on the logical network (auto-allocate IP from the pool).
    $nicName = "$($Vm.Name)-nic"
    $nicExists = Invoke-Az -Args @('stack-hci-vm','network','nic','list','-g',$Config.ResourceGroup,
        '--query',"[?name=='$nicName'].name",'-o','tsv') -Raw
    if ([string]::IsNullOrWhiteSpace(($nicExists | Out-String).Trim())) {
        Write-Step "Creating NIC '$nicName' on lnet '$lnetName'..."
        if ($PSCmdlet.ShouldProcess($nicName, "create nic")) {
            $null = Invoke-Az -MustSucceed -Args @('stack-hci-vm','network','nic','create',
                '-g',$Config.ResourceGroup,'--custom-location',$CustomLocationId,'--location',$Config.Location,
                '--name',$nicName,'--subnet-id',$lnetId)
        }
    } else { Write-Step "NIC '$nicName' already exists - reusing." 'SKIP' }

    # 2) Data disks (created up front; attached at VM create).
    $dataDiskIds = @()
    foreach ($d in $Vm.DataDisks) {
        $diskExists = Invoke-Az -Args @('stack-hci-vm','disk','list','-g',$Config.ResourceGroup,
            '--query',"[?name=='$($d.Name)'].name",'-o','tsv') -Raw
        if ([string]::IsNullOrWhiteSpace(($diskExists | Out-String).Trim())) {
            Write-Step "Creating data disk '$($d.Name)' ($($d.SizeGb) GB, $($d.Purpose))..."
            if ($PSCmdlet.ShouldProcess($d.Name, "create disk")) {
                $null = Invoke-Az -MustSucceed -Args @('stack-hci-vm','disk','create',
                    '-g',$Config.ResourceGroup,'--custom-location',$CustomLocationId,'--location',$Config.Location,
                    '--name',$d.Name,'--size-gb',"$($d.SizeGb)",'--storage-path-id',$storagePathId,'--dynamic','true')
            }
        } else { Write-Step "Data disk '$($d.Name)' already exists - reusing." 'SKIP' }
        $dataDiskIds += "/subscriptions/$subId/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.AzureStackHCI/virtualHardDisks/$($d.Name)"
    }

    # 3) Create the VM, sized correctly AT CREATE TIME (guest agent on; attach data disks if any).
    #    Azure Local sizes VMs via `--hardware-profile memory-mb=<MB> processors=<N>` (static
    #    memory) on `create` - this is the only mechanism that boots the VM correctly so the
    #    in-guest VM config agent installs. (NOTE: `--hardware-profile` is accepted by `create`
    #    but is NOT shown in `az stack-hci-vm create --help` for ext 1.14.5 - verified empirically;
    #    see docs/upstream/azure-local/manage/create-arc-virtual-machines.md.) Do NOT use `--size`:
    #    an Azure SKU name (e.g. Standard_D2s_v3) OR the `Default` keyword both yield an unbootable
    #    0-CPU/0-MB VM whose guest agent never installs. Post-create `update` resize cannot revive
    #    a VM born at 0/0, so sizing MUST happen here at create.
    Write-Step "Creating VM '$($Vm.Name)' ($($Vm.VCpus) vCPU / $($Vm.MemoryMb) MB, image=$($img.ImageName))..."
    $createArgs = @('stack-hci-vm','create','-g',$Config.ResourceGroup,'--custom-location',$CustomLocationId,
        '--location',$Config.Location,'--name',$Vm.Name,'--computer-name',$Vm.Name,
        '--image',$img.ImageName,'--storage-path-id',$storagePathId,
        '--hardware-profile',"memory-mb=$($Vm.MemoryMb)","processors=$($Vm.VCpus)",
        '--admin-username',$Config.AdminUsername,'--admin-password',$AdminPassword,
        '--nics',$nicName,'--os-type',$img.OsType,'--enable-agent','true')
    if ($dataDiskIds.Count -gt 0) { $createArgs += @('--attach-data-disks'); $createArgs += $dataDiskIds }
    if ($PSCmdlet.ShouldProcess($Vm.Name, "create vm ($($Vm.VCpus) vCPU / $($Vm.MemoryMb) MB)")) {
        $null = Invoke-Az -MustSucceed -Args $createArgs
        Write-Step "VM '$($Vm.Name)' created." 'OK'
    }
    return $Vm.Name
}

function Test-WorkloadVmDomain {
    <# Returns the joined domain (or workgroup) reported by the guest, via Arc runCommand. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$VmName)
    return (Invoke-ArcRunCommand -Config $Config -VmName $VmName -Script '(Get-CimInstance Win32_ComputerSystem).Domain' -TimeoutSeconds 120).Trim()
}

function Join-VmToDomain {
    <# Domain-join the guest via run-command. Pre-checks DNS resolution of the domain first.
       Idempotent: returns early if the guest already reports the target domain. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$VmName,
        [string]$AdminPassword
    )
    $fqdn = $Config.Domain.Fqdn
    $netbios = $Config.Domain.NetbiosPrefix
    $current = Test-WorkloadVmDomain -Config $Config -VmName $VmName
    if ($current -like "*$fqdn*") {
        Write-Step "VM '$VmName' already joined to '$fqdn' - skipping." 'SKIP'
        return $true
    }
    if (-not $AdminPassword) { $AdminPassword = Resolve-AdminPassword }

    # Build the in-guest join script. DNS pre-check guards against the vlan200->DC path being down.
    $ouArg = if ($Config.Domain.OuPath) { "-OUPath '$($Config.Domain.OuPath)'" } else { '' }
    $joinScript = @"
`$ErrorActionPreference='Stop'
`$dns = '$($Config.LogicalNetwork.DnsServers[0])'
if (-not (Resolve-DnsName -Name '$fqdn' -Server `$dns -ErrorAction SilentlyContinue)) {
    Write-Output "DNS_FAIL: cannot resolve $fqdn via `$dns"; exit 1
}
`$sec = ConvertTo-SecureString '$AdminPassword' -AsPlainText -Force
`$cred = New-Object System.Management.Automation.PSCredential('$netbios\Administrator', `$sec)
Add-Computer -DomainName '$fqdn' -Credential `$cred $ouArg -Force -ErrorAction Stop
Write-Output 'JOIN_OK'
Restart-Computer -Force
"@
    Write-Step "Domain-joining VM '$VmName' to '$fqdn'..."
    if ($PSCmdlet.ShouldProcess($VmName, "domain join $fqdn")) {
        $text = (Invoke-ArcRunCommand -Config $Config -VmName $VmName -Script $joinScript -TimeoutSeconds 300).Trim()
        if ($text -match 'DNS_FAIL') { throw "Domain join '$VmName': $text (check the vlan200->DC routing/DNS)." }
        if ($text -notmatch 'JOIN_OK') { Write-Step "Join output for '$VmName': $text" 'WARN' }
        else { Write-Step "VM '$VmName' domain-join submitted (rebooting)." 'OK' }
    }
    return $true
}

function Set-SqlStoragePaths {
    <# Post-config the SQL VM: initialize/format the data + tempdb disks and point SQL at them.
       Idempotent-ish: formatting skips disks already partitioned; SQL ALTERs are re-runnable. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$VmName)
    $script = @'
$ErrorActionPreference = 'Stop'
# Initialize + format any RAW data disks, assigning drive letters in order.
$letters = @('F','G','H','I')
$i = 0
Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Sort-Object Number | ForEach-Object {
    $dl = $letters[$i]; $i++
    $_ | Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter $dl -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "DATA$dl" -AllocationUnitSize 65536 -Confirm:$false | Out-Null
    New-Item -ItemType Directory -Force -Path "$($dl):\SQLDATA" | Out-Null
}
# If SQL is present, point default data/log at first data disk and move tempdb to the next.
$svc = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
if ($svc) {
    Import-Module SqlServer -ErrorAction SilentlyContinue
    $dataDrive = (Get-Volume | Where-Object FileSystemLabel -like 'DATA*' | Sort-Object DriveLetter | Select-Object -First 1).DriveLetter
    $tempDrive = (Get-Volume | Where-Object FileSystemLabel -like 'DATA*' | Sort-Object DriveLetter | Select-Object -Skip 1 -First 1).DriveLetter
    if ($dataDrive) {
        New-Item -ItemType Directory -Force -Path "$($dataDrive):\SQLDATA" | Out-Null
        sqlcmd -Q "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'DefaultData',REG_SZ,N'$($dataDrive):\SQLDATA'" 2>$null
        sqlcmd -Q "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'DefaultLog',REG_SZ,N'$($dataDrive):\SQLDATA'" 2>$null
    }
    if ($tempDrive) {
        New-Item -ItemType Directory -Force -Path "$($tempDrive):\SQLTEMP" | Out-Null
        sqlcmd -Q "ALTER DATABASE tempdb MODIFY FILE (NAME=tempdev, FILENAME='$($tempDrive):\SQLTEMP\tempdb.mdf'); ALTER DATABASE tempdb MODIFY FILE (NAME=templog, FILENAME='$($tempDrive):\SQLTEMP\templog.ldf');" 2>$null
        Restart-Service -Name 'MSSQLSERVER' -Force
    }
    Write-Output ("SQL_POSTCONFIG_OK data=" + $dataDrive + " temp=" + $tempDrive)
} else {
    Write-Output 'SQL_NOT_PRESENT (disks formatted only)'
}
'@
    Write-Step "Post-configuring SQL storage on '$VmName'..."
    if ($PSCmdlet.ShouldProcess($VmName, "sql storage post-config")) {
        $res = Invoke-ArcRunCommand -Config $Config -VmName $VmName -Script $script -TimeoutSeconds 600
        Write-Step "SQL post-config result: $(( $res | Out-String).Trim())" 'OK'
    }
}

function Add-AvdSessionHost {
    <# Install the AVD agent + boot loader in-guest with the host-pool registration token.
       Assumes the VM exists, is domain-joined, and the Connected Machine agent is present
       (enabled at create via --enable-agent). Idempotent: skips if agent already installed. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$RegistrationToken
    )
    $script = @"
`$ErrorActionPreference='Stop'
# Skip if already registered (boot loader present).
if (Get-Service -Name 'RDAgentBootLoader' -ErrorAction SilentlyContinue) {
    Write-Output 'AVD_AGENT_ALREADY_INSTALLED'; return
}
`$tmp = 'C:\AVDAgent'; New-Item -ItemType Directory -Force -Path `$tmp | Out-Null
`$agent = Join-Path `$tmp 'RDAgent.msi'
`$boot  = Join-Path `$tmp 'RDBootLoader.msi'
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2310011' -OutFile `$agent -UseBasicParsing
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2311028' -OutFile `$boot  -UseBasicParsing
Start-Process msiexec -ArgumentList "/i `$agent /quiet /qn REGISTRATIONTOKEN=$RegistrationToken" -Wait
Start-Process msiexec -ArgumentList "/i `$boot /quiet /qn" -Wait
Write-Output 'AVD_AGENT_INSTALLED'
"@
    Write-Step "Installing AVD agent on '$VmName'..."
    if ($PSCmdlet.ShouldProcess($VmName, "install AVD agent")) {
        $res = Invoke-ArcRunCommand -Config $Config -VmName $VmName -Script $script -TimeoutSeconds 900
        Write-Step "AVD agent result on '$VmName': $(( $res | Out-String).Trim())" 'OK'
    }
}

Export-ModuleMember -Function `
    Ensure-MarketplaceImage, Wait-ImageReady, Ensure-WorkloadLogicalNetwork, `
    New-WorkloadVm, Join-VmToDomain, Test-WorkloadVmDomain, Set-SqlStoragePaths, `
    Add-AvdSessionHost, Resolve-CustomLocationId, Resolve-AdminPassword, Invoke-ArcRunCommand
