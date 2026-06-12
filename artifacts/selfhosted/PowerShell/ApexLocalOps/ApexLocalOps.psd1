@{
  # =========================================================================
  # apex-localops - ApexLocalOps module manifest.
  #
  # A clean-room, ZERO-Jumpstart PowerShell module that builds a nested Azure
  # Local environment on a single Windows Server cluster-host VM: it pulls the
  # operator-staged ISOs from blob storage, converts them to bootable VHDXs,
  # creates a nested domain controller and N Azure Local nodes, Arc-registers
  # the nodes, and drives the cluster validate -> deploy.
  #
  # Replaces the Azure.Arc.Jumpstart.* Gallery modules entirely.
  # =========================================================================

  RootModule        = 'ApexLocalOps.psm1'
  ModuleVersion     = '0.1.0'
  GUID              = 'b6f4e2a1-9c3d-4f7e-8a1b-2d5c6e7f8a90'
  Author            = 'apex-localops'
  CompanyName       = 'apex-localops'
  Copyright         = '(c) apex-localops. MIT licensed.'
  Description       = 'Clean-room nested Azure Local build (no Jumpstart dependency).'
  PowerShellVersion = '5.1'

  # Functions exposed to Bootstrap.ps1 / New-ApexLocalCluster.ps1.
  FunctionsToExport = @(
    # Common
    'Get-ApexConfig'
    'Write-ApexLog'
    'Connect-ApexAzure'
    'Set-ApexProgress'
    'Send-ApexLogsToStorage'
    # Image pipeline
    'Wait-ApexStagedIso'
    'Get-ApexStagedIso'
    'Convert-ApexIsoToVhdx'
    # Host fabric
    'New-ApexHostSwitch'
    'New-ApexRouterVM'
    # Nested build
    'New-ApexUnattendXml'
    'New-ApexNestedVM'
    'Wait-ApexVMReady'
    'New-ApexDomainController'
    'New-ApexLocalNode'
    'Connect-ApexNodeToArc'
    'Set-ApexNodeTimeSync'
    # Cluster
    'Invoke-ApexLocalClusterDeploy'
  )

  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData       = @{
    PSData = @{
      Tags       = @('AzureLocal', 'AzureStackHCI', 'HyperV', 'apex-localops')
      LicenseUri = 'https://github.com/jonathan-vella/apex-localops/blob/main/LICENSE'
      ProjectUri = 'https://github.com/jonathan-vella/apex-localops'
    }
  }
}
