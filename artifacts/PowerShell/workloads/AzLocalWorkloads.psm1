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

function Get-WorkloadVmInstance {
    <# Return the Azure Local VM instance (virtualMachineInstances/default) object, or $null if
       the VM does not exist yet. Uses the ARM REST path because `stack-hci-vm show --query`
       returns empty for these resources. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$VmName)
    $url = "https://management.azure.com/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.HybridCompute/machines/$VmName/providers/Microsoft.AzureStackHCI/virtualMachineInstances/default?api-version=2024-01-01"
    return (Invoke-Az -Args @('rest', '--method', 'get', '--url', $url))
}

function Get-VmDomainJoinState {
    <# Return the provisioningState of the JsonADDomainExtension on the VM ('Succeeded',
       'Failed', 'Creating', ...), or 'NotFound' if the extension isn't present. This is the
       reliable ARM-side signal for domain join (no in-guest run-command needed). #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$VmName)
    $url = "https://management.azure.com/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.HybridCompute/machines/$VmName/extensions/domainJoinExtension?api-version=2025-01-13"
    $r = Invoke-Az -Args @('rest', '--method', 'get', '--url', $url)
    if ($r -and $r.properties) { return $r.properties.provisioningState }
    return 'NotFound'
}

function New-WorkloadVm {
    <# Deploy ONE Azure Local VM by deploying the canonical vm.bicep template: an Arc machine
       (with a system-assigned identity, for zero-touch guest-agent onboarding) + a NIC on the
       logical network + data disks + a correctly-sized VM instance, and - when $Vm.DomainJoin
       is set - an AD domain join via the JsonADDomainExtension (no in-guest run-command).
       Declarative and idempotent (ARM no-ops unchanged resources). Returns the VM name.

       Sizing is applied AT CREATE via hardwareProfile.vmSize='Custom' + processors + memoryMB,
       the only reliable mechanism: the CLI `--hardware-profile` path (without vm-size='Custom')
       silently produces an unbootable 0-CPU/0-MB VM. See infra/.../workloads/vm.bicep. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Vm,                 # one entry from $Config.Vms
        [string]$AdminPassword,                    # resolved by caller (not stored)
        [int]$StoragePathIndex = 0,
        [switch]$SkipDomainJoin,
        [string]$TemplateFile
    )
    if (-not $TemplateFile) {
        $TemplateFile = Join-Path $PSScriptRoot '../../../infra/bicep/azlocal-js/workloads/vm.bicep'
    }
    if (-not (Test-Path $TemplateFile)) { throw "VM template not found: $TemplateFile" }
    $TemplateFile = (Resolve-Path $TemplateFile).Path

    $img = $Config.Images[$Vm.ImageKey]
    if (-not $img) { throw "VM '$($Vm.Name)': ImageKey '$($Vm.ImageKey)' not found in Config.Images." }
    $storagePathId = $Config.StoragePathIds[$StoragePathIndex % $Config.StoragePathIds.Count]
    $doJoin = [bool]$Vm.DomainJoin -and -not $SkipDomainJoin

    # Idempotency: skip if the VM already exists (and, when joining, the join already succeeded).
    $existing = Get-WorkloadVmInstance -Config $Config -VmName $Vm.Name
    if ($existing) {
        if (-not $doJoin) {
            Write-Step "VM '$($Vm.Name)' already exists (state=$($existing.properties.provisioningState)) - skipping." 'SKIP'
            return $Vm.Name
        }
        if ((Get-VmDomainJoinState -Config $Config -VmName $Vm.Name) -eq 'Succeeded') {
            Write-Step "VM '$($Vm.Name)' already exists and is domain-joined - skipping." 'SKIP'
            return $Vm.Name
        }
        Write-Step "VM '$($Vm.Name)' exists but not yet domain-joined - redeploying to add the join." 'INFO'
    }

    # Password is only needed to actually deploy; skip resolving it on a -WhatIf dry run.
    if (-not $AdminPassword -and -not $WhatIfPreference) { $AdminPassword = Resolve-AdminPassword }

    # Data-disk parameter as a JSON array matching vm.bicep's dataDiskType ({name,diskSizeGB,dynamic}).
    $disks = foreach ($d in $Vm.DataDisks) { [ordered]@{ name = $d.Name; diskSizeGB = $d.SizeGb; dynamic = $true } }
    $disksJson = ConvertTo-Json -InputObject @($disks) -AsArray -Compress -Depth 5

    $deployParams = @(
        "name=$($Vm.Name)", "location=$($Config.Location)",
        "vCPUCount=$($Vm.VCpus)", "memoryMB=$($Vm.MemoryMb)",
        "adminUsername=$($Config.AdminUsername)", "adminPassword=$AdminPassword",
        "imageName=$($img.ImageName)", "isMarketplaceImage=true",
        "hciLogicalNetworkName=$($Config.LogicalNetwork.Name)",
        "customLocationName=$($Config.CustomLocationName)",
        "storagePathId=$storagePathId", "dataDiskParams=$disksJson"
    )
    $joinSuffix = ''
    if ($doJoin) {
        $joinUser = if ($Config.Domain.JoinUsername) { $Config.Domain.JoinUsername } else { 'Administrator' }
        $deployParams += @("domainToJoin=$($Config.Domain.Fqdn)", "domainJoinUserName=$joinUser", "domainJoinPassword=$AdminPassword")
        if ($Config.Domain.OuPath) { $deployParams += "domainTargetOu=$($Config.Domain.OuPath)" }
        $joinSuffix = " + domain join $($Config.Domain.Fqdn)"
    }

    $depName = "vm-$($Vm.Name)-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
    $action = "deploy vm.bicep ($($Vm.VCpus) vCPU / $($Vm.MemoryMb) MB$joinSuffix)"
    Write-Step "Deploying VM '$($Vm.Name)': $action ..."
    if ($PSCmdlet.ShouldProcess($Vm.Name, $action)) {
        $null = Invoke-Az -MustSucceed -Args (@('deployment', 'group', 'create', '-g', $Config.ResourceGroup,
                '--name', $depName, '--template-file', $TemplateFile, '-o', 'none', '--parameters') + $deployParams)
        Write-Step "VM '$($Vm.Name)' deployment completed." 'OK'
        if ($doJoin) {
            $state = Get-VmDomainJoinState -Config $Config -VmName $Vm.Name
            if ($state -eq 'Succeeded') { Write-Step "VM '$($Vm.Name)' domain-join extension = Succeeded." 'OK' }
            else { Write-Step "VM '$($Vm.Name)' domain-join extension state = $state - verify before dependent steps." 'WARN' }
        }
    }
    return $Vm.Name
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
    New-WorkloadVm, Get-WorkloadVmInstance, Get-VmDomainJoinState, Set-SqlStoragePaths, `
    Add-AvdSessionHost, Resolve-CustomLocationId, Resolve-AdminPassword, Invoke-ArcRunCommand
