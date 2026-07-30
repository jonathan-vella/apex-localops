<#
.SYNOPSIS
    AzLocalWorkloads - idempotent helpers to deploy post-cluster workloads (VMs + AVD
    session host) on the Azure Local cluster.

.DESCRIPTION
    Runs FROM THE DEV CONTAINER (or any client) with operator `az` credentials. Every
    operation is a cloud/ARM call: VM/disk/NIC/image/lnet via the `stack-hci-vm` extension
    (custom location + Arc), and in-guest steps via the Microsoft.HybridCompute
    machines/runCommands API (Invoke-ArcRunCommand) - so nothing needs to run on
    the cluster host and there is no run-command-extension wedge risk.

    Every function is ADDITIVE and IDEMPOTENT: it inspects current state and skips/echoes
    when the target already exists, so the whole module is safe to re-run and never
    modifies the cluster or its infrastructure logical network.

    No secrets are stored in the repo. The VM/domain admin password is supplied by the caller:
    from the LOCALSELF_ADMIN_PASSWORD (or WORKLOADS_ADMIN_PASSWORD) environment variable, or a
    local git-ignored password file (LOCALSELF_ADMIN_PASSWORD_FILE, default
    ~/.apex-localops/admin-password) - never committed, never logged.

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
    $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'SKIP' { 'DarkGray' } default { 'Cyan' } }
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
        if ($MustSucceed) {
            # Redact secret parameter values before surfacing the failed command.
            $safeArgs = $Args | ForEach-Object { $_ -replace '(?i)(password|token)=.+', '$1=***' }
            $safeOut = ($out -join "`n") -replace '(?i)(password|token)=[^ ]+', '$1=***'
            throw "az $($safeArgs -join ' ') failed ($code): $safeOut"
        }
        return $null
    }
    if ($Raw) { return ($out -join "`n") }
    $text = ($out -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return $text | ConvertFrom-Json } catch { return $text }
}

function Resolve-AdminPassword {
    <# Resolve the VM/domain admin password in priority order:
         1. LOCALSELF_ADMIN_PASSWORD / WORKLOADS_ADMIN_PASSWORD environment variable.
         2. A local password FILE that is never committed - the path in
            LOCALSELF_ADMIN_PASSWORD_FILE, else the default ~/.apex-localops/admin-password.
       The file lets an operator type the lab password once into a git-ignored file (the lab is
       already gated by Azure MFA) instead of re-exporting it in every new shell. Trailing
       newlines are trimmed; the value is never logged or written back to disk. #>
    param()
    foreach ($var in 'LOCALSELF_ADMIN_PASSWORD', 'WORKLOADS_ADMIN_PASSWORD') {
        $val = [Environment]::GetEnvironmentVariable($var)
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    }
    $file = [Environment]::GetEnvironmentVariable('LOCALSELF_ADMIN_PASSWORD_FILE')
    if ([string]::IsNullOrWhiteSpace($file)) { $file = Join-Path $HOME '.apex-localops/admin-password' }
    if (Test-Path -LiteralPath $file) {
        $val = (Get-Content -LiteralPath $file -Raw -ErrorAction Stop).TrimEnd("`r", "`n")
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
        throw "Admin password file '$file' is empty."
    }
    throw "Admin password not set. Export LOCALSELF_ADMIN_PASSWORD, or write it to a local file (LOCALSELF_ADMIN_PASSWORD_FILE, default ~/.apex-localops/admin-password) that is never committed."
}

function Resolve-ClusterContext {
    <# Resolve identity/cluster-specific values from the target resource group so the tooling
       is reusable across tenants: subscription (from the az context), the single custom
       location, the Azure Local instance region, and the cluster's *-InfraLNET. Blank config
       values are filled IN PLACE; any value already set is respected as an override. #>
    param([Parameter(Mandatory)]$Config)
    if ([string]::IsNullOrWhiteSpace($Config.SubscriptionId)) {
        $Config.SubscriptionId = ([string](Invoke-Az -MustSucceed -Args @('account', 'show', '--query', 'id', '-o', 'tsv') -Raw)).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Config.CustomLocationName)) {
        $Config.CustomLocationName = ([string](Invoke-Az -Args @('customlocation', 'list', '-g', $Config.ResourceGroup, '--query', '[0].name', '-o', 'tsv') -Raw)).Trim()
        if ([string]::IsNullOrWhiteSpace($Config.CustomLocationName)) { throw "No custom location found in $($Config.ResourceGroup)." }
    }
    if ([string]::IsNullOrWhiteSpace($Config.Location)) {
        $Config.Location = ([string](Invoke-Az -Args @('customlocation', 'show', '-g', $Config.ResourceGroup, '-n', $Config.CustomLocationName, '--query', 'location', '-o', 'tsv') -Raw)).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($Config.VmLogicalNetworkName)) {
        # VMs need a DEDICATED tenant lnet - the platform blocks tenant NICs on the *-InfraLNET.
        # Derive its L2 (subnet/VLAN/gateway/DNS) from the InfraLNET so VMs share the DC's subnet
        # and domain join needs no routing; only the IP pool is a lab choice (.60-.120 of the /24).
        $vm = $Config.LogicalNetworks.Vm
        $infra = Invoke-Az -Args @('stack-hci-vm', 'network', 'lnet', 'list', '-g', $Config.ResourceGroup,
            '--query', "[?ends_with(name,'InfraLNET')] | [0]", '-o', 'json')
        if ($infra -and $infra.properties.subnets) {
            $sp = $infra.properties.subnets[0].properties
            if ([string]::IsNullOrWhiteSpace($vm.AddressPrefix)) { $vm.AddressPrefix = [string]$sp.addressPrefix }
            if ([string]::IsNullOrWhiteSpace("$($vm.Vlan)")) { $vm.Vlan = [int]$sp.vlan }
            if ([string]::IsNullOrWhiteSpace($vm.Gateway)) {
                $def = @($sp.routeTable.properties.routes) | Where-Object { $_.properties.addressPrefix -in '0.0.0.0', '0.0.0.0/0' } | Select-Object -First 1
                if ($def) { $vm.Gateway = [string]$def.properties.nextHopIpAddress }
            }
            if (-not $vm.DnsServers -or @($vm.DnsServers).Count -eq 0) { $vm.DnsServers = @($infra.properties.dhcpOptions.dnsServers) }
            $base = ([string]$sp.addressPrefix -split '/')[0] -replace '\.\d+$', ''
            if ([string]::IsNullOrWhiteSpace($vm.IpPoolStart)) { $vm.IpPoolStart = "$base.60" }
            if ([string]::IsNullOrWhiteSpace($vm.IpPoolEnd)) { $vm.IpPoolEnd = "$base.120" }
        }
        $Config.VmLogicalNetworkName = $vm.Name
    }
    Write-Step "Resolved: sub=$($Config.SubscriptionId) rg=$($Config.ResourceGroup) cl=$($Config.CustomLocationName) region=$($Config.Location) vmLnet=$($Config.VmLogicalNetworkName)" 'INFO'
}

function Resolve-CustomLocationId {
    <# Return the custom location resource id. Resolves the single custom location in the RG
       when the config leaves CustomLocationName blank (reusable across deployments). #>
    param([Parameter(Mandatory)]$Config)
    if ([string]::IsNullOrWhiteSpace($Config.CustomLocationName)) {
        $id = ([string](Invoke-Az -Args @('customlocation', 'list', '-g', $Config.ResourceGroup, '--query', '[0].id', '-o', 'tsv') -Raw)).Trim()
    }
    else {
        $id = ([string](Invoke-Az -Args @('customlocation', 'show', '-g', $Config.ResourceGroup, '-n', $Config.CustomLocationName, '--query', 'id', '-o', 'tsv') -Raw)).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($id)) { throw "No custom location found in $($Config.ResourceGroup)." }
    return $id
}

function Invoke-ArcRunCommand {
    <# Execute a PowerShell script inside an Azure Local Arc machine via the HybridCompute
       machines/runCommands API - works from any client with ARM access (no in-guest
       agent CLI, no `az vm run-command` wedge). Synchronous: submits the runCommand,
       polls to a terminal executionState, returns combined stdout+stderr, then deletes
       the runCommand resource (cleanup). API version = latest GA (2025-01-13). Optional
       -Parameters / -ProtectedParameters (name=value hashtables) are passed to the script's
       param() block by name; ProtectedParameters are encrypted and never returned in GET,
       so use them for secrets (passwords, tokens). #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$Parameters = @{},
        [hashtable]$ProtectedParameters = @{},
        [int]$TimeoutSeconds = 600,
        [int]$PollSeconds = 15,
        [string]$ApiVersion = '2025-01-13'
    )
    $sub = $Config.SubscriptionId
    $rg = $Config.ResourceGroup
    $rcName = "alw-$([guid]::NewGuid().ToString('N').Substring(0,12))"
    $idBase = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$VmName/runCommands/$rcName"
    $putUrl = "$idBase`?api-version=$ApiVersion"
    $getUrl = "$idBase`?api-version=$ApiVersion&`$expand=instanceView"
    $props = @{
        source           = @{ script = $Script }
        asyncExecution   = $false
        timeoutInSeconds = $TimeoutSeconds
    }
    if ($Parameters.Count) {
        $props.parameters = @($Parameters.GetEnumerator() | ForEach-Object { @{ name = $_.Key; value = [string]$_.Value } })
    }
    if ($ProtectedParameters.Count) {
        $props.protectedParameters = @($ProtectedParameters.GetEnumerator() | ForEach-Object { @{ name = $_.Key; value = [string]$_.Value } })
    }
    $body = @{ location = $Config.Location; properties = $props } | ConvertTo-Json -Depth 8
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $body -Encoding utf8
    try {
        $null = Invoke-Az -MustSucceed -Args @('rest', '--method', 'put', '--url', $putUrl, '--body', "@$tmp")
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds + 180)
        $state = $null; $output = ''; $errout = ''
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $PollSeconds
            $r = Invoke-Az -Args @('rest', '--method', 'get', '--url', $getUrl)
            if (-not $r) { continue }
            $iv = $r.properties.instanceView
            $state = if ($iv) { $iv.executionState } else { $null }
            if ($state -in @('Succeeded', 'Failed', 'TimedOut', 'Canceled')) {
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
        $null = Invoke-Az -Args @('rest', '--method', 'delete', '--url', $putUrl)   # best-effort cleanup
    }
}

function Get-ClusterNodeNames {
    <# Resolve the single Azure Local cluster in the resource group and return an object with its
       name (.Cluster) and node names (.Nodes, from reportedProperties.nodes[].name). Generic and
       reusable - no hard-coded cluster/node name prefix, so it works in any tenant. #>
    param([Parameter(Mandatory)]$Config)
    $cluster = ([string](Invoke-Az -Args @('stack-hci', 'cluster', 'list', '-g', $Config.ResourceGroup, '--query', '[0].name', '-o', 'tsv') -Raw)).Trim()
    if (-not $cluster) { return [pscustomobject]@{ Cluster = $null; Nodes = @() } }
    $nodes = @(Invoke-Az -Args @('stack-hci', 'cluster', 'show', '-g', $Config.ResourceGroup, '-n', $cluster, '--query', 'reportedProperties.nodes[].name', '-o', 'json'))
    return [pscustomobject]@{ Cluster = $cluster; Nodes = $nodes }
}

function Sync-ClusterNodeTime {
    <# Force a w32tm time resync on every Azure Local cluster node (via the Arc run-command
       API) so client<->node clock skew can't break image/VM/VHD creation. Azure Local stores
       VHDs on the cluster CSV over SMB/Kerberos; when a node's clock drifts >5 min from the
       client the CreateFile fails with "There is a time and/or date difference between the
       client and server", failing the deployment. Running this as a preflight makes image +
       VM creation reliable in constrained (nested / high-latency) labs. Non-fatal: warns per
       node that can't be resynced. Returns the number of nodes resynced. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Config)
    $ctx = Get-ClusterNodeNames -Config $Config
    if (-not $ctx.Cluster) { Write-Step 'No Azure Local cluster found in the resource group - skipping node time sync.' 'WARN'; return 0 }
    if (-not $ctx.Nodes -or $ctx.Nodes.Count -eq 0) { Write-Step "No nodes reported for cluster '$($ctx.Cluster)' - skipping node time sync." 'WARN'; return 0 }
    $script = 'Start-Service w32time -ErrorAction SilentlyContinue; w32tm /resync /rediscover /force | Out-Null; Start-Sleep -Seconds 2; (Get-Date).ToUniversalTime().ToString("o")'
    $count = 0
    foreach ($node in $ctx.Nodes) {
        if ($PSCmdlet.ShouldProcess($node, 'w32tm /resync (clock-skew preflight)')) {
            try {
                $t = Invoke-ArcRunCommand -Config $Config -VmName $node -Script $script -TimeoutSeconds 120
                Write-Step "Node '$node' time resynced => $(([string]$t).Trim())" 'OK'
                $count++
            }
            catch { Write-Step "Node '$node' time resync failed (continuing): $($_.Exception.Message)" 'WARN' }
        }
    }
    return $count
}

function Get-VmHostNode {
    <# Find which Azure Local cluster node currently hosts a given VM (matched by Hyper-V VM
       name), so the guest can be reached over PowerShell Direct (VMBus). Returns the node name,
       or $null if the VM isn't found on any node. Reusable across tenants. #>
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$VmName)
    $ctx = Get-ClusterNodeNames -Config $Config
    if (-not $ctx.Nodes -or $ctx.Nodes.Count -eq 0) { return $null }
    $probe = "if (Get-VM -Name '$VmName' -ErrorAction SilentlyContinue) { 'FOUND' } else { 'no' }"
    foreach ($node in $ctx.Nodes) {
        try {
            $r = [string](Invoke-ArcRunCommand -Config $Config -VmName $node -Script $probe -TimeoutSeconds 90)
            if ($r -match 'FOUND') { return $node }
        }
        catch { Write-Step "Locating '$VmName': probe on node '$node' failed (continuing): $($_.Exception.Message)" 'WARN' }
    }
    return $null
}

function Invoke-GuestDomainJoin {
    <# EXPERIMENTAL / OPT-IN - USE WITH CAUTION. Domain-join an Azure Local guest via PowerShell
       Direct from its hosting cluster node, a fallback for when the in-guest Azure Arc agent hasn't
       onboarded (so the declarative JsonADDomainExtension can't run). WARNING: running PowerShell
       Direct (Invoke-Command -VMName) from a HybridCompute runCommand has been observed to WEDGE the
       node's runCommand handler (all further runCommands on that node fail until the node is
       rebooted) - prefer fixing guest->Azure egress so the agent onboards, or joining from the VM
       console. It runs over the Hyper-V VMBus, so it needs NO guest->Azure
       network path; the join itself only needs the guest to reach the domain controller on its own
       subnet. Secrets (the guest local-admin password and the domain join password) are passed to
       the node via runCommand *protectedParameters* (encrypted, write-only, never returned in GET) -
       never embedded in the script text. Idempotent: a guest already in the domain returns success
       with no change. Non-fatal: returns $false and warns if the join can't be completed. Reusable
       across tenants (all names/identities come from $Config). Returns $true on success. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$AdminPassword
    )
    $node = Get-VmHostNode -Config $Config -VmName $VmName
    if (-not $node) { Write-Step "Could not locate VM '$VmName' on any cluster node - cannot host-join." 'WARN'; return $false }
    Write-Step "PowerShell-Direct host join is EXPERIMENTAL and can wedge node '$node' runCommand handler - opt-in only." 'WARN'
    $guestUser = $Config.AdminUsername
    $joinUser = if ($Config.Domain.JoinUsername) { $Config.Domain.JoinUsername } else { 'Administrator' }
    $fqdn = $Config.Domain.Fqdn
    $ou = if ($Config.Domain.OuPath) { [string]$Config.Domain.OuPath } else { '' }
    if (-not $PSCmdlet.ShouldProcess($VmName, "domain join $fqdn via PowerShell Direct on node '$node'")) { return $false }
    # This script runs ON the node; it opens PowerShell Direct into the guest and joins the domain.
    # The guest credential form varies (plain / .\ / <computer>\), so it tries the common forms.
    $nodeScript = @'
param([string]$GuestUser,[string]$Fqdn,[string]$JoinUser,[string]$Ou,[string]$Vm,[string]$GuestPass,[string]$JoinPass)
$ErrorActionPreference = 'Stop'
$secGuest = ConvertTo-SecureString $GuestPass -AsPlainText -Force
$dcred = New-Object System.Management.Automation.PSCredential("$Fqdn\$JoinUser", (ConvertTo-SecureString $JoinPass -AsPlainText -Force))
$inner = {
    param($d, $c, $o)
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.PartOfDomain -and $cs.Domain -eq $d) { return 'ALREADY_JOINED' }
    $p = @{ DomainName = $d; Credential = $c; Force = $true; ErrorAction = 'Stop' }
    if ($o) { $p['OUPath'] = $o }
    Add-Computer @p
    return 'JOIN_STAGED'
}
$result = $null; $lastErr = $null
foreach ($u in @($GuestUser, "$Vm\$GuestUser", ".\$GuestUser")) {
    try {
        $local = New-Object System.Management.Automation.PSCredential($u, $secGuest)
        $result = Invoke-Command -VMName $Vm -Credential $local -ScriptBlock $inner -ArgumentList $Fqdn, $dcred, $Ou -ErrorAction Stop
        break
    }
    catch { $lastErr = $_.Exception.Message }
}
if (-not $result) { Write-Output "JOIN_FAILED: $lastErr"; return }
Write-Output $result
if ($result -eq 'JOIN_STAGED') {
    try {
        $local = New-Object System.Management.Automation.PSCredential($GuestUser, $secGuest)
        Invoke-Command -VMName $Vm -Credential $local -ScriptBlock { Restart-Computer -Force } -ErrorAction SilentlyContinue
    }
    catch { }
    Write-Output 'REBOOT_ISSUED'
}
'@
    $params = @{ GuestUser = $guestUser; Fqdn = $fqdn; JoinUser = $joinUser; Ou = $ou; Vm = $VmName }
    $protected = @{ GuestPass = $AdminPassword; JoinPass = $AdminPassword }
    try {
        $out = [string](Invoke-ArcRunCommand -Config $Config -VmName $node -Script $nodeScript -Parameters $params -ProtectedParameters $protected -TimeoutSeconds 300)
    }
    catch {
        Write-Step "Host-based domain join of '$VmName' failed: $($_.Exception.Message)" 'WARN'; return $false
    }
    if ($out -match 'ALREADY_JOINED') { Write-Step "VM '$VmName' already domain-joined to $fqdn (host check)." 'SKIP'; return $true }
    if ($out -match 'JOIN_STAGED') { Write-Step "VM '$VmName' domain-joined to $fqdn via PowerShell Direct on '$node' (rebooting to finalize)." 'OK'; return $true }
    Write-Step "Host-based domain join of '$VmName' did not complete: $out" 'WARN'; return $false
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
    $existing = Invoke-Az -Args @('stack-hci-vm', 'image', 'list', '-g', $Config.ResourceGroup,
        '--query', "[?name=='$ImageName'].{n:name,p:properties.provisioningState}", '-o', 'json')
    if ($existing -and $existing.Count -gt 0) {
        $state = $existing[0].p
        if ($state -eq 'Failed') {
            Write-Step "Image '$ImageName' exists but is Failed - leaving as-is (manual cleanup recommended)." 'WARN'
        }
        else {
            Write-Step "Image '$ImageName' already present (state=$state) - skipping create." 'SKIP'
        }
        return $ImageName
    }
    if (-not $CustomLocationId) { $CustomLocationId = Resolve-CustomLocationId -Config $Config }
    Write-Step "Creating image '$ImageName' from URN '$Urn' (this downloads several GB into the CSV)..."
    if ($PSCmdlet.ShouldProcess($ImageName, "create marketplace image")) {
        $null = Invoke-Az -MustSucceed -Args @('stack-hci-vm', 'image', 'create',
            '-g', $Config.ResourceGroup, '--custom-location', $CustomLocationId,
            '--location', $Config.Location, '--name', $ImageName, '--os-type', $OsType,
            '--urn', $Urn)
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
        $img = Invoke-Az -Args @('stack-hci-vm', 'image', 'list', '-g', $Config.ResourceGroup,
            '--query', "[?name=='$ImageName'].properties.provisioningState", '-o', 'tsv') -Raw
        $state = ($img | Out-String).Trim()
        if ($state -eq 'Succeeded') { Write-Step "Image '$ImageName' = Succeeded." 'OK'; return $true }
        if ($state -eq 'Failed') { throw "Image '$ImageName' provisioning Failed." }
        Write-Step "Image '$ImageName' state='$state' - waiting..." 'INFO'
        Start-Sleep -Seconds $PollSeconds
    }
    throw "Timed out after $TimeoutMinutes min waiting for image '$ImageName'."
}

# -----------------------------------------------------------------------------
# Phase 2 - Logical network (idempotent; reuses the existing vlan200 lnet)
# -----------------------------------------------------------------------------

function Ensure-WorkloadLogicalNetwork {
    <# Ensure every logical network in $Config.LogicalNetworks exists. Entries flagged
       ReuseExisting are VERIFIED only (never created). All others are created idempotently -
       the tenant VM lnet (derived from the InfraLNET's L2) and the pre-staged AKS lnet. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)]$Config, [string]$CustomLocationId)
    foreach ($key in $Config.LogicalNetworks.Keys) {
        $ln = $Config.LogicalNetworks[$key]
        # Blank Name on a reused entry => the resolved InfraLNET (VmLogicalNetworkName).
        $lnName = if ($ln.Name) { $ln.Name } else { $Config.VmLogicalNetworkName }
        $found = Invoke-Az -Args @('stack-hci-vm', 'network', 'lnet', 'list', '-g', $Config.ResourceGroup,
            '--query', "[?name=='$lnName'].name", '-o', 'tsv') -Raw
        $exists = -not [string]::IsNullOrWhiteSpace(($found | Out-String).Trim())
        if ($ln.ReuseExisting) {
            if ($exists) { Write-Step "Logical network '$lnName' exists (reused for VMs) - not modified." 'SKIP' }
            else { throw "Reused logical network '$lnName' not found; the cluster must create it first." }
            continue
        }
        if ($exists) { Write-Step "Logical network '$lnName' already exists - skipping create." 'SKIP'; continue }
        if (-not $CustomLocationId) { $CustomLocationId = Resolve-CustomLocationId -Config $Config }
        Write-Step "Creating logical network '$lnName' (vlan $($ln.Vlan), $($ln.AddressPrefix))..."
        if ($PSCmdlet.ShouldProcess($lnName, "create logical network")) {
            $null = Invoke-Az -MustSucceed -Args @('stack-hci-vm', 'network', 'lnet', 'create',
                '-g', $Config.ResourceGroup, '--custom-location', $CustomLocationId, '--location', $Config.Location,
                '--name', $lnName, '--vm-switch-name', $Config.VmSwitchName,
                '--ip-allocation-method', 'static', '--address-prefixes', $ln.AddressPrefix,
                '--gateway', $ln.Gateway, '--dns-servers', ($ln.DnsServers -join ' '), '--vlan', "$($ln.Vlan)",
                '--ip-pool-start', $ln.IpPoolStart, '--ip-pool-end', $ln.IpPoolEnd)
            Write-Step "Logical network '$lnName' created." 'OK'
        }
    }
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

function Wait-VmAgentConnected {
    <# Poll the VM's Azure Arc Connected Machine agent until it reports Connected, or the
       timeout elapses. On Azure Local the in-guest Arc agent onboards AFTER the VM instance is
       created (the moc guest agent installs it), and guest extensions - e.g. the domain-join
       JsonADDomainExtension - can only run once the machine is Connected to Azure. Returns
       $true when connected; $false on timeout. Non-fatal by design: the caller defers the
       dependent step so VM creation is never blocked by a slow/absent guest agent. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$VmName,
        [int]$TimeoutMinutes = 15,
        [int]$PollSeconds = 30
    )
    $url = "https://management.azure.com/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.ResourceGroup)/providers/Microsoft.HybridCompute/machines/$VmName" + '?api-version=2025-01-13'
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Step "Waiting up to $TimeoutMinutes min for VM '$VmName' Arc agent to connect to Azure..."
    $status = $null
    do {
        $m = Invoke-Az -Args @('rest', '--method', 'get', '--url', $url)
        # StrictMode-safe: a machine with a failed/absent VMI has no 'status' member yet.
        $status = if ($m -and $m.properties -and $m.properties.PSObject.Properties['status']) { $m.properties.status } else { $null }
        if ($status -eq 'Connected') {
            Write-Step "VM '$VmName' Arc agent = Connected (agent $($m.properties.agentVersion))." 'OK'
            return $true
        }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds $PollSeconds
    } while ($true)
    Write-Step "VM '$VmName' Arc agent still '$status' after $TimeoutMinutes min." 'WARN'
    return $false
}

function New-WorkloadVm {
    <# Deploy ONE Azure Local VM from the canonical vm.bicep template: an Arc machine (with a
       system-assigned identity, for zero-touch guest-agent onboarding) + a NIC on the logical
       network + data disks + a correctly-sized VM instance. When $Vm.DomainJoin is set, the AD
       domain join (JsonADDomainExtension) is applied as a SEPARATE second phase, DECOUPLED from
       VM creation: the in-guest Arc agent onboards only after the VM instance exists, so the
       function first creates the VM, then waits (bounded) for the agent and applies the join. If
       the agent never connects, it falls back to a host-based join over PowerShell Direct (from the
       hosting node, via the Hyper-V VMBus); if that too is unavailable the join is deferred (not
       fatal) and a later re-run retries it - VM creation is therefore never blocked by a slow or
       absent guest agent. Declarative
       and idempotent (ARM no-ops unchanged resources; each phase is skipped when already done).
       Returns the VM name.

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
        [switch]$EnableHostJoinFallback,           # OPT-IN: PowerShell-Direct host join (risky - see Invoke-GuestDomainJoin)
        [int]$JoinAgentTimeoutMinutes = 5,         # bounded wait for the in-guest Arc agent
        [string]$TemplateFile
    )
    if (-not $TemplateFile) {
        $TemplateFile = Join-Path $PSScriptRoot '../../../../infra/bicep/azlocal-selfhosted/workloads/vm.bicep'
    }
    if (-not (Test-Path $TemplateFile)) { throw "VM template not found: $TemplateFile" }
    $TemplateFile = (Resolve-Path $TemplateFile).Path

    $img = $Config.Images[$Vm.ImageKey]
    if (-not $img) { throw "VM '$($Vm.Name)': ImageKey '$($Vm.ImageKey)' not found in Config.Images." }
    $storagePathId = $Config.StoragePathIds[$StoragePathIndex % $Config.StoragePathIds.Count]
    $doJoin = [bool]$Vm.DomainJoin -and -not $SkipDomainJoin

    # Idempotency: is the VM instance already present, and (when joining) is the join already done?
    $existing = Get-WorkloadVmInstance -Config $Config -VmName $Vm.Name
    $joinDone = $doJoin -and $existing -and ((Get-VmDomainJoinState -Config $Config -VmName $Vm.Name) -eq 'Succeeded')
    if ($existing) {
        if (-not $doJoin) {
            Write-Step "VM '$($Vm.Name)' already exists (state=$($existing.properties.provisioningState)) - skipping." 'SKIP'
            return $Vm.Name
        }
        if ($joinDone) {
            Write-Step "VM '$($Vm.Name)' already exists and is domain-joined - skipping." 'SKIP'
            return $Vm.Name
        }
        Write-Step "VM '$($Vm.Name)' exists but not yet domain-joined - will wait for the Arc agent and apply the join." 'INFO'
    }

    # Password is only needed to actually deploy; skip resolving it on a -WhatIf dry run.
    if (-not $AdminPassword -and -not $WhatIfPreference) { $AdminPassword = Resolve-AdminPassword }

    # Data-disk parameter as a JSON array matching vm.bicep's dataDiskType ({name,diskSizeGB,dynamic}).
    # Guard the empty case: an unguarded foreach yields [[]] which fails template validation.
    $disks = @(foreach ($d in $Vm.DataDisks) { [ordered]@{ name = $d.Name; diskSizeGB = $d.SizeGb; dynamic = $true } })
    $disksJson = if ($disks.Count) { ConvertTo-Json -InputObject $disks -AsArray -Compress -Depth 5 } else { '[]' }

    # Per-VM target logical network (defaults to the dedicated tenant lnet) + optional static IP.
    $lnetName = if ($Vm.LogicalNetworkName) { $Vm.LogicalNetworkName } else { $Config.VmLogicalNetworkName }

    # Base (VM-only) parameters. Domain-join params are added ONLY in phase 2 so a slow/absent
    # in-guest Arc agent never blocks VM creation - the two concerns are decoupled + retryable.
    $baseParams = @(
        "name=$($Vm.Name)", "location=$($Config.Location)",
        "vCPUCount=$($Vm.VCpus)", "memoryMB=$($Vm.MemoryMb)",
        "adminUsername=$($Config.AdminUsername)", "adminPassword=$AdminPassword",
        "imageName=$($img.ImageName)", "isMarketplaceImage=true",
        "hciLogicalNetworkName=$lnetName",
        "customLocationName=$($Config.CustomLocationName)",
        "storagePathId=$storagePathId", "dataDiskParams=$disksJson"
    )
    if ($Vm.PrivateIp) { $baseParams += "privateIPAddress=$($Vm.PrivateIp)" }

    # ---- Phase 1: create the VM instance (no domain join) ----
    if (-not $existing) {
        $depName = "vm-$($Vm.Name)-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
        $action = "deploy vm.bicep ($($Vm.VCpus) vCPU / $($Vm.MemoryMb) MB)"
        Write-Step "Deploying VM '$($Vm.Name)': $action ..."
        if ($PSCmdlet.ShouldProcess($Vm.Name, $action)) {
            $null = Invoke-Az -MustSucceed -Args (@('deployment', 'group', 'create', '-g', $Config.ResourceGroup,
                    '--name', $depName, '--template-file', $TemplateFile, '-o', 'none', '--parameters') + $baseParams)
            Write-Step "VM '$($Vm.Name)' created." 'OK'
        }
    }

    # ---- Phase 2: domain join (decoupled + retryable) ----
    if ($doJoin -and -not $joinDone) {
        $joinUser = if ($Config.Domain.JoinUsername) { $Config.Domain.JoinUsername } else { 'Administrator' }
        $joinParams = $baseParams + @("domainToJoin=$($Config.Domain.Fqdn)", "domainJoinUserName=$joinUser", "domainJoinPassword=$AdminPassword")
        if ($Config.Domain.OuPath) { $joinParams += "domainTargetOu=$($Config.Domain.OuPath)" }
        $action = "domain join $($Config.Domain.Fqdn) (JsonADDomainExtension)"
        if ($PSCmdlet.ShouldProcess($Vm.Name, $action)) {
            # The extension runs via the in-guest Arc agent, which onboards AFTER the VM exists.
            # Wait (bounded) for it; if it never connects, defer so the VM stage still succeeds.
            if (Wait-VmAgentConnected -Config $Config -VmName $Vm.Name -TimeoutMinutes $JoinAgentTimeoutMinutes) {
                $depName = "vm-$($Vm.Name)-join-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
                Write-Step "Applying $action to '$($Vm.Name)' ..."
                $null = Invoke-Az -MustSucceed -Args (@('deployment', 'group', 'create', '-g', $Config.ResourceGroup,
                        '--name', $depName, '--template-file', $TemplateFile, '-o', 'none', '--parameters') + $joinParams)
                $state = Get-VmDomainJoinState -Config $Config -VmName $Vm.Name
                if ($state -eq 'Succeeded') { Write-Step "VM '$($Vm.Name)' domain-join extension = Succeeded." 'OK' }
                else { Write-Step "VM '$($Vm.Name)' domain-join extension state = $state - verify before dependent steps." 'WARN' }
            }
            else {
                # The Arc agent didn't onboard in time. Default = DEFER (safe). The PS-Direct
                # fallback is OPT-IN only (-EnableHostJoinFallback) because it can wedge a node's
                # runCommand handler; prefer fixing guest->Azure egress so the agent onboards.
                if ($EnableHostJoinFallback -and $AdminPassword -and (Invoke-GuestDomainJoin -Config $Config -VmName $Vm.Name -AdminPassword $AdminPassword)) {
                    Write-Step "VM '$($Vm.Name)' domain joined via opt-in PowerShell Direct fallback (Arc agent absent)." 'OK'
                }
                else {
                    Write-Step "VM '$($Vm.Name)' domain join DEFERRED (Arc agent not connected). Re-run after fixing guest->Azure egress so the agent onboards, or join from the VM console." 'WARN'
                }
            }
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
    New-WorkloadVm, Get-WorkloadVmInstance, Get-VmDomainJoinState, Wait-VmAgentConnected, Set-SqlStoragePaths, `
    Add-AvdSessionHost, Resolve-ClusterContext, Resolve-CustomLocationId, Resolve-AdminPassword, `
    Invoke-ArcRunCommand, Sync-ClusterNodeTime, Get-ClusterNodeNames, Get-VmHostNode, Invoke-GuestDomainJoin
