@{
  # =============================================================================
  # Workloads-Config.psd1 (SELF-HOSTED) - declarative config for post-cluster
  # workloads on the self-hosted Azure Local cluster
  # (rg-apexlocal / apexlocal, registered canadacentral, domain apexlocal.local).
  #
  # Consumed by AzLocalWorkloads.psm1 + Deploy-AzLocalWorkloads.ps1, run FROM THE
  # DEV CONTAINER with operator `az login`. NO SECRETS IN THE REPO: the VM/domain admin password
  # is read at runtime from $LOCALSELF_ADMIN_PASSWORD, or a local git-ignored file
  # ($LOCALSELF_ADMIN_PASSWORD_FILE, default ~/.apex-localops/admin-password); never committed.
  #
  # REUSABLE ACROSS TENANTS: identity/cluster-specific values below are left BLANK and
  # RESOLVED at runtime from the target resource group (subscription from `az login`, the
  # single custom location, the instance region, and the cluster's *-InfraLNET). Point the
  # tooling at your RG with --resource-group; only the lab choices (VM names/IPs/sizes,
  # image + AVD names) are hard defaults you can override. Everything is ADDITIVE.
  # =============================================================================

  # --- Target scope (blank = resolved at runtime; set a value to pin it) ------
  SubscriptionId       = ''    # resolved from `az account show`
  ResourceGroup        = 'rg-apexlocal'    # the self-hosted deploy default; override with --resource-group
  Location             = ''    # resolved from the custom location (the Azure Local instance region)
  CustomLocationName   = ''    # resolved: the single custom location in the resource group

  # --- Existing fabric (referenced, never recreated) --------------------------
  # The default compute switch Azure Local creates for the Compute_Management intent.
  VmSwitchName         = 'ConvergedSwitch(compute_management)'

  # Tenant VMs get their OWN logical network - the platform blocks tenant NICs on the
  # *-InfraLNET. It is created on the SAME L2 as the DC (subnet/VLAN/gateway/DNS derived
  # from the InfraLNET at runtime), so domain join needs no VLAN or nested-router change.
  VmLogicalNetworkName = ''    # resolved: the dedicated tenant lnet (LogicalNetworks.Vm.Name)

  # Logical networks the 'network' stage ensures. The VM lnet is a DEDICATED tenant network
  # created on the DC's L2 (blank fields below are derived from the *-InfraLNET at runtime);
  # the AKS network is pre-created for the future AKS plan (its router route and VIP wiring
  # land with that plan). Both VLANs are inside the node trunk range 0-1000.
  LogicalNetworks      = @{
    Vm  = @{
      Name          = 'apexlocal-vmlnet'   # dedicated tenant lnet (InfraLNET forbids tenant NICs)
      AddressPrefix = ''    # derived from *-InfraLNET (same subnet as the DC)
      Gateway       = ''    # derived from InfraLNET default-route next-hop
      DnsServers    = @()   # derived from InfraLNET DNS (the DC)
      Vlan          = ''    # derived from InfraLNET (untagged 0 in this lab)
      IpPoolStart   = ''    # derived: .60 of the InfraLNET /24 (override for non-/24 subnets)
      IpPoolEnd     = ''    # derived: .120 of the InfraLNET /24
      ReuseExisting = $false
    }
    Aks = @{
      Name          = 'aks-lnet-vlan110'
      AddressPrefix = '10.10.0.0/24'
      Gateway       = '10.10.0.1'
      DnsServers    = @('192.168.1.254')
      Vlan          = 110
      IpPoolStart   = '10.10.0.101'
      IpPoolEnd     = '10.10.0.199'
      ReuseExisting = $false
    }
  }

  # --- Storage path (CSV) for image + VM placement --------------------------
  # Empty string => Azure Local picks an automatic high-availability path. Keeps the
  # config portable (no hard-coded storage container GUIDs).
  StoragePathIds       = @('')

  # --- Marketplace images -----------------------------------------------------
  # ImageName = the gallery image resource name on the cluster (what VMs reference).
  # Urn = publisher:offer:sku (Azure Local curated catalog). All Gen2.
  Images               = @{
    WindowsServer2025 = @{
      ImageName = 'ws2025-azure-edition-smalldisk'
      Urn       = 'microsoftwindowsserver:windowsserver:2025-datacenter-azure-edition-smalldisk:latest'
      OsType    = 'Windows'
    }
    Sql2022           = @{
      ImageName = 'sql2022-std-ws2022'
      Urn       = 'microsoftsqlserver:sql2022-ws2022:standard-gen2:latest'
      OsType    = 'Windows'
    }
    Win11Avd          = @{
      ImageName = 'win11-25h2-avd-m365'
      Urn       = 'microsoftwindowsdesktop:office-365:win11-25h2-avd-m365:latest'
      OsType    = 'Windows'
    }
  }

  # --- Domain join (nested AD; creds resolved at runtime, never stored) --------
  # vm.bicep joins declaratively via the JsonADDomainExtension as '<Fqdn>\<JoinUsername>'
  # with the runtime admin password. The DC (apexlocal-dc, 192.168.1.254) is the DNS server.
  Domain               = @{
    Fqdn         = 'apexlocal.local'
    NetbiosName  = 'APEXLOCAL'
    JoinUsername = 'Administrator'    # domain account with rights to join computers
    OuPath       = $null             # null => default Computers container
  }

  # --- VM admin (local, created at provision time) ----------------------------
  AdminUsername        = 'azureuser'

  # --- Workload VM definitions ------------------------------------------------
  # Azure Local sizes VMs by EXPLICIT vCPU + memory (vm.bicep sets vmSize='Custom').
  # PrivateIp assigns a static address on the dedicated tenant VM lnet (same subnet as the DC).
  # LogicalNetworkName blank => the resolved VmLogicalNetworkName (the tenant VM lnet).
  Vms                  = @{
    # apexws01-03 (.60/.61/.63) were abandoned after a moc-operator wedge left their VMIs stuck 'Failed'; the live pair is apexws04/05.
    WindowsServer2025_1 = @{
      Name               = 'apexws04'          # <=15 chars for NetBIOS/domain join
      ImageKey           = 'WindowsServer2025'
      VCpus              = 2
      MemoryMb           = 8192                # 8 GB
      DomainJoin         = $true
      LogicalNetworkName = ''
      PrivateIp          = '192.168.1.64'
      DataDisks          = @()
    }
    WindowsServer2025_2 = @{
      Name               = 'apexws05'
      ImageKey           = 'WindowsServer2025'
      VCpus              = 2
      MemoryMb           = 8192
      DomainJoin         = $true
      LogicalNetworkName = ''
      PrivateIp          = '192.168.1.65'
      DataDisks          = @()
    }
    # Defined for the FUTURE SQL plan (not deployed by this plan's stages).
    Sql2022             = @{
      Name               = 'apexsql01'
      ImageKey           = 'Sql2022'
      VCpus              = 4
      MemoryMb           = 16384               # 16 GB
      DomainJoin         = $true
      LogicalNetworkName = ''
      PrivateIp          = '192.168.1.62'
      DataDisks          = @(
        @{ Name = 'apexsql01-data'; SizeGb = 128; Purpose = 'data' }
        @{ Name = 'apexsql01-tempdb'; SizeGb = 64; Purpose = 'tempdb' }
      )
    }
    AvdHost             = @{
      Name               = 'apexavd01'
      ImageKey           = 'Win11Avd'
      VCpus              = 4
      MemoryMb           = 16384               # 16 GB
      DomainJoin         = $true
      LogicalNetworkName = ''
      PrivateIp          = '192.168.1.70'
      DataDisks          = @()
    }
  }

  # --- AVD control plane (Azure-side; deployed by operator via Bicep) ----------
  Avd                  = @{
    HostPoolName          = 'apexlocal-hp01'
    WorkspaceName         = 'apexlocal-ws01'
    AppGroupName          = 'apexlocal-dag01'  # Desktop application group
    MetadataLocation      = 'canadacentral'    # AVD metadata region (control plane)
    HostPoolType          = 'Pooled'
    LoadBalancerType      = 'BreadthFirst'
    PreferredAppGroupType = 'Desktop'
    ManagementType        = 'Standard'         # NOT "session host configuration" (unsupported on Azure Local)
    MaxSessionLimit       = 5
    SessionHostVmKey      = 'AvdHost'
  }
}
