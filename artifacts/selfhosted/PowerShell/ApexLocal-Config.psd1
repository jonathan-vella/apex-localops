@{

  # ===========================================================================
  # apex-localops - Azure Local SELF-HOSTED profile · in-VM configuration.
  #
  # Single source of truth for the cluster-host build: filesystem layout, the
  # internal Hyper-V network, the nested domain controller + Azure Local node
  # geometry, the staged ISO blob names, and the cluster deployment inputs.
  #
  # Consumed by Bootstrap.ps1, New-ApexLocalCluster.ps1, and the ApexLocalOps
  # module. Bootstrap.ps1 overrides the network / node / domain values from the
  # parameters passed by the host's Custom Script Extension where applicable.
  #
  # NOTE ON NAMING: this profile is a clean-room build with ZERO dependency on
  # Jumpstart. The AD domain is deliberately named 'apexlocal.local' (not the
  # Jumpstart-era 'jumpstart.local') to keep the result free of Jumpstart-isms.
  # ===========================================================================

  # Host filesystem layout. C: is the OS disk; V: is the pooled Premium data
  # disks (holds the converted base VHDXs + the nested VM differencing disks).
  Paths        = @{
    RootDir     = 'C:\ApexLocal'
    LogsDir     = 'C:\ApexLocal\Logs'
    IsoDir      = 'C:\ApexLocal\iso'        # ISOs pulled from blob land here
    ToolsDir    = 'C:\ApexLocal\Tools'
    ModuleDir   = 'C:\ApexLocal\ApexLocalOps'
    BaseVhdDir  = 'V:\ApexLocal\base'       # converted bootable base VHDXs
    VmVhdDir    = 'V:\ApexLocal\vhd'        # per-VM differencing disks
    VmDir       = 'V:\ApexLocal\vms'        # VM configuration files
    AnswerDir   = 'V:\ApexLocal\answer'     # generated unattend / answer files
  }

  # Blob names the operator stages into the storage account from the jumpbox.
  # Both are Microsoft-owned, portal/eval gated, and CANNOT be vendored into the
  # repo - so they are downloaded on the jumpbox and uploaded here. The host
  # watcher blocks until BOTH are present, then pulls them with its managed
  # identity (no storage keys).
  Artifacts    = @{
    Container          = 'iso-images'
    AzureLocalIsoBlob  = 'AzureLocalOS.iso'   # portal-gated Azure Local OS ISO
    WindowsServerBlob  = 'WindowsServer.iso'   # Windows Server 2025 (DC base)
    LogsContainer      = 'logs'                # host uploads build logs here
  }

  # Internal Hyper-V network. A single internal switch + host NAT provides the
  # management/Arc path for the nested nodes and DC. The Azure Local STORAGE
  # intents (StorageA/StorageB) are added as additional adapters per node by the
  # ApexLocalOps fabric step - see New-ApexLocalCluster.ps1.
  Network      = @{
    SwitchName     = 'ApexLocal-Internal'
    NatName        = 'ApexLocal-NAT'
    SubnetPrefix   = '192.168.1.0/24'
    Gateway        = '192.168.1.1'
    PrefixLength   = 24
    DnsServers     = @('192.168.1.254')   # the nested DC is authoritative DNS
    # Azure-VM IMDS endpoint denied on every nested adapter BEFORE first boot so
    # a nested node never picks up the Azure HOST VM's managed identity/metadata.
    ImdsAddress    = '169.254.169.254'
  }

  # Active Directory domain hosted by the nested DC (created on the cluster host).
  Domain       = @{
    Fqdn         = 'apexlocal.local'
    NetBiosName  = 'APEXLOCAL'          # <= 15 chars
    DcHostName   = 'apexlocal-dc'       # <= 15 chars
    DcIpAddress  = '192.168.1.254'
    # OU for the Azure Local deployment objects. MUST NOT be at the domain root.
    OuPath       = 'OU=ApexLocal,DC=apexlocal,DC=local'
    OuName       = 'ApexLocal'
    # Local + domain admin used by the in-VM build and the cluster deploy. The
    # passwords are injected from the host CSE env vars at runtime, never stored.
    SafeModeUser = 'Administrator'
  }

  # Azure Local cluster nodes (nested Gen2 VMs on the cluster host). Default is a
  # 3-node cluster (odd quorum, no witness). Bootstrap.ps1 can override Count and
  # the per-node memory from the CSE parameters.
  Cluster      = @{
    NodeCount        = 3
    NamePrefix       = 'apexlocal-n'    # -> apexlocal-n1 / -n2 / -n3
    NodeMemoryMB     = 98304            # 96 GB per node
    NodeCpuCount     = 16
    Generation       = 2
    # First node IP; subsequent nodes increment the last octet.
    NodeStartIp      = '192.168.1.11'
    # Contiguous management IP block for Azure Local + Arc Resource Bridge.
    # Must be >= 6 addresses and must NOT overlap the node/DC/gateway IPs.
    StartingIp       = '192.168.1.20'
    EndingIp         = '192.168.1.30'
    SubnetMask       = '255.255.255.0'
    DefaultGateway   = '192.168.1.1'
    # Storage intent adapters (switchless / converged on the single internal net
    # for this nested lab). Real hardware uses dedicated RDMA NICs.
    StorageVlanA     = 711
    StorageVlanB     = 712
    # Witness: 'None' for 3 nodes (odd quorum); 'Cloud' required for 2 nodes.
    WitnessType      = 'None'
  }

  # Resource-group tag keys used to surface in-VM progress to
  # scripts/monitor-selfhosted.sh (mirrors the SFF SffProgress/SffStatus model).
  Tags         = @{
    ProgressKey = 'ApexProgress'
    StatusKey   = 'ApexStatus'
  }

  # In-VM build progress milestones (written to the ProgressKey tag, in order).
  Milestones   = @(
    'Initializing'
    'HyperVInstalling'
    'HyperVInstalled'
    'NetworkConfigured'
    'AwaitingIsos'
    'IsosStaged'
    'BaseImagesConverted'
    'DomainControllerReady'
    'NodesCreated'
    'NodesArcConnected'
    'ClusterValidating'
    'ClusterDeploying'
    'Completed'
    'Failed'
  )
}
