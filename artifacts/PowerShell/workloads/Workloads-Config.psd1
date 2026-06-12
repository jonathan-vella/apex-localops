@{
  # =============================================================================
  # Workloads-Config.psd1 - declarative config for post-cluster workloads on the
  # Azure Local cluster (rg-azlocal-swc01 / localboxcluster, registered westeurope).
  #
  # Consumed by AzLocalWorkloads.psm1 + Deploy-AzLocalWorkloads.ps1 (run in-VM on
  # LocalBox-Client via `az login --identity`). NO SECRETS here: the VM/domain admin
  # password is read at runtime from C:\LocalBox\LocalBox-Config.psd1 (SDNAdminPassword).
  #
  # Values below were captured from the LIVE cluster on 2026-06-12 (read-only preflight).
  # Everything this drives is ADDITIVE - it never modifies cluster or InfraLNET config.
  # =============================================================================

  # --- Target scope -----------------------------------------------------------
  SubscriptionId     = '00858ffc-dded-4f0f-8bbf-e17fff0d47d9'
  ResourceGroup      = 'rg-azlocal-swc01'
  Location           = 'westeurope'          # region the Azure Local instance is registered in
  CustomLocationName = 'jumpstart'           # rbCustomLocationName; id resolved at runtime

  # --- Existing fabric (already provisioned; referenced, never recreated) -----
  VmSwitchName       = 'ConvergedSwitch(compute_management)'

  LogicalNetwork     = @{
    Name          = 'localbox-vm-lnet-vlan200'   # exists: Static, 192.168.200.0/24 pool .0-.255, vlan 200
    AddressPrefix = '192.168.200.0/24'
    Gateway       = '192.168.200.1'
    DnsServers    = @('192.168.1.254')           # nested DC (jumpstartdc) so domain join resolves
    Vlan          = 200
    IpPoolStart   = '192.168.200.50'             # only used IF the lnet must be (re)created; existing pool is .0-.255
    IpPoolEnd     = '192.168.200.150'
  }

  # --- Storage paths (CSV) for image + VM placement; round-robin across the three ---
  StoragePathIds     = @(
    '/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-azlocal-swc01/providers/Microsoft.AzureStackHCI/storageContainers/UserStorage1-88767a0cc58d47e6a02918361018f80d'
    '/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-azlocal-swc01/providers/Microsoft.AzureStackHCI/storageContainers/UserStorage2-66a44d80efc3421f9f72ca9be4c81fe7'
    '/subscriptions/00858ffc-dded-4f0f-8bbf-e17fff0d47d9/resourceGroups/rg-azlocal-swc01/providers/Microsoft.AzureStackHCI/storageContainers/UserStorage3-e8f612efef614d04b6a8208e4ad11c28'
  )

  # --- Marketplace images (ALL THREE ALREADY EXIST + Succeeded as of 2026-06-12) ---
  # ImageName = the gallery image resource name on the cluster (what VMs reference).
  # Urn = publisher:offer:sku - used only by the idempotent Ensure-MarketplaceImage to
  # (re)create the image if a matching one is ever missing. Verified in the curated
  # Azure Local Marketplace catalog (Microsoft Learn, 2026-06-12).
  Images             = @{
    WindowsServer2025 = @{
      ImageName = '2025-datacenter-azure-edition-01'
      Urn       = 'microsoftwindowsserver:windowsserver:2025-datacenter-azure-edition-core'
      OsType    = 'Windows'
    }
    Sql2022           = @{
      ImageName = 'sql-std-2022-gen2-01'
      Urn       = 'microsoftsqlserver:sql2022-ws2022:standard-gen2'
      OsType    = 'Windows'
    }
    Win11Avd          = @{
      ImageName = 'win11-25h2-avd-m365-01'
      Urn       = 'microsoftwindowsdesktop:office-365:win11-25h2-avd-m365'
      OsType    = 'Windows'
    }
  }

  # --- Domain join (nested AD; creds resolved at runtime, never stored) --------
  Domain             = @{
    Fqdn          = 'jumpstart.local'
    NetbiosPrefix = 'jumpstart'            # join user = jumpstart\Administrator
    # OU left null => default Computers container
    OuPath        = $null
  }

  # --- VM admin (local) -------------------------------------------------------
  # AdminUsername is the in-guest local admin created at VM provision time.
  # Password is read at runtime from LocalBox-Config.psd1 (SDNAdminPassword) - NOT stored.
  AdminUsername      = 'arcdemo'

  # --- Workload VM definitions ------------------------------------------------
  # Azure Local sizes VMs by EXPLICIT vCPU + memory, NOT Azure SKU names. `az stack-hci-vm
  # create` only has a free-form --size (an Azure SKU name there yields 0 CPU / 0 MB, an
  # unbootable VM). The supported knobs are `az stack-hci-vm update --v-cpus-available N
  # --memory-mb MB` (vmSize then shows as "Custom"). New-WorkloadVm creates then resizes.
  # Sizes stay modest (nested nodes are ~96 GB RAM each). memory-mb must be a multiple of 4.
  Vms                = @{
    WindowsServer2025 = @{
      Name       = 'azl-ws2025-01'           # <=15 chars for NetBIOS/domain join
      ImageKey   = 'WindowsServer2025'
      VCpus      = 2
      MemoryMb   = 8192                      # 8 GB
      DomainJoin = $true
      DataDisks  = @(
        @{ Name = 'azl-ws2025-01-data'; SizeGb = 128; Purpose = 'data' }
      )
    }
    Sql2022           = @{
      Name       = 'azl-sql2022-01'
      ImageKey   = 'Sql2022'
      VCpus      = 4
      MemoryMb   = 16384                     # 16 GB
      DomainJoin = $true
      DataDisks  = @(
        @{ Name = 'azl-sql2022-01-data'; SizeGb = 128; Purpose = 'data' }
        @{ Name = 'azl-sql2022-01-tempdb'; SizeGb = 64; Purpose = 'tempdb' }
      )
    }
    AvdHost           = @{
      Name       = 'azl-avd-01'
      ImageKey   = 'Win11Avd'
      VCpus      = 4
      MemoryMb   = 16384                     # 16 GB
      DomainJoin = $true
      DataDisks  = @()
    }
  }

  # --- AVD control plane (Azure-side; deployed by operator via Bicep) ----------
  Avd                = @{
    HostPoolName          = 'azl-hp01'
    WorkspaceName         = 'azl-ws01'
    AppGroupName          = 'azl-dag01'      # Desktop application group
    MetadataLocation      = 'westeurope'     # AVD metadata region (control plane)
    HostPoolType          = 'Pooled'
    LoadBalancerType      = 'BreadthFirst'
    PreferredAppGroupType = 'Desktop'
    ManagementType        = 'Standard'       # NOT "session host configuration" (unsupported on Azure Local)
    MaxSessionLimit       = 5
    SessionHostVmKey      = 'AvdHost'        # which Vms entry is the session host
  }
}
