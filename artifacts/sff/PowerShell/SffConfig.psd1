@{

  # =========================================================================
  # apex-localops - Azure Local Small Form Factor (SFF) in-VM configuration.
  # Single source of truth for paths, the internal Hyper-V NAT network, and the
  # nested SFF test VM geometry. Consumed by Bootstrap-Sff.ps1, Stage-SffArtifacts.ps1,
  # and New-SffTestVm.ps1. Bootstrap-Sff.ps1 may override the network/VM values from
  # the parameters passed by the host's Custom Script Extension.
  # =========================================================================

  # Host filesystem layout (drive V: is the attached Premium data disk).
  Paths     = @{
    RootDir     = "C:\LocalSFF"
    LogsDir     = "C:\LocalSFF\Logs"
    IncomingDir = "C:\LocalSFF\incoming"
    IsoDir      = "C:\LocalSFF\iso"
    ToolsDir    = "C:\LocalSFF\Tools"
    VhdDir      = "V:\LocalSFF\vhd"
    VmDir       = "V:\LocalSFF\vms"
  }

  # Blob names the operator stages into the storage account. The portal "Download all"
  # produces a ZIP archive for the Maintenance OS (extract to get the .iso) and the
  # Configurator App as an .msix. The watcher accepts either the extracted roe.iso OR the
  # roe.zip archive (it extracts the .iso), and treats the Configurator as optional.
  Artifacts = @{
    RoeIsoBlob        = "roe.iso"
    RoeZipBlob        = "roe.zip"
    ConfiguratorBlobs = @("configurator.msi", "configurator.msix")
  }

  # Internal Hyper-V NAT network (created by the vendored set-network.ps1, WinNAT mode).
  Network   = @{
    SwitchName   = "HV-Internal-NAT"
    Mode         = "WinNAT"
    SubnetPrefix = "192.168.200.0/24"
    Gateway      = "192.168.200.1"
    DnsServers   = @("1.1.1.1", "8.8.8.8")
  }

  # Nested SFF test VM - fixed to satisfy the Learn "Review your VM setup" gate:
  # Generation 2 - TPM ON - Secure Boot OFF - >= 4 vCPU - 16000 MB - 256 GB VHD.
  NestedVm  = @{
    Name               = "linuxsff-vm"
    MemoryMB           = 16000
    CpuCount           = 4
    DiskGB             = 256
    Generation         = 2
    # Number of nested SFF test VMs to build inside the host (>=1). With Count>1 each
    # instance gets a suffixed name (<Name>-<n>), a deterministic static MAC + DHCP
    # reservation, and its own Key Vault voucher secret (<VoucherSecretName>-<n>). The
    # host VM must be sized to fit Count x (CpuCount vCPU, MemoryMB) plus host overhead.
    Count              = 1
    # Azure-VM IMDS endpoint that must be denied on the nested adapter before boot.
    ImdsAddress        = "169.254.169.254"
    # Success signal the ROE/maintenance OS prints when ready. Regex (matched case-
    # insensitively) covering both documented wordings: "[Succeeded] ROE setup completed
    # successfully" and "Status: [Succeeded] Maintenance environment setup completed
    # successfully".
    RoeSuccessPattern  = "(ROE setup completed successfully|Maintenance environment setup completed successfully|setup completed successfully)"
    # Minutes to wait for the ROE success signal before flagging it for manual check.
    RoeTimeoutMinutes  = 20
    # First DHCP lease on the internal NAT scope (.50-.200) - the nested VM's address.
    # Used as the PRIMARY readiness probe: SSH(22) reachable here == ROE maintenance OS up.
    # Instance n (1-based) is reserved at <subnet>.(BaseIpHostOctet + n - 1): .50, .51, ...
    IpAddress          = "192.168.200.50"
    BaseIpHostOctet    = 50
    # Static MAC prefix (Hyper-V OUI 00:15:5D + 5FF0 marker). The last octet is the
    # 1-based instance index, giving 00:15:5D:5F:F0:01, ...:02. A matching DHCP
    # reservation pins each MAC to its IpAddress so readiness/voucher probes are deterministic.
    MacPrefix          = "00155D5FF0"
    # Base name of the Key Vault secret that holds the ownership voucher. With Count>1
    # each instance stores to "<VoucherSecretName>-<n>"; Count==1 keeps the bare name.
    VoucherSecretName  = "sff-ownership-voucher"
    # ROE in nested Hyper-V intermittently needs ONE reboot to finish maintenance-env setup
    # (observed repeatedly). If SSH(22) is not up after this many minutes, the builder
    # performs a single automatic Restart-VM nudge instead of requiring a manual reboot.
    RebootAfterMinutes = 8
  }

  # Resource-group tag keys used to surface in-VM progress to monitor-sff.sh.
  Tags      = @{
    ProgressKey = "SffProgress"
    StatusKey   = "SffStatus"
  }
}
