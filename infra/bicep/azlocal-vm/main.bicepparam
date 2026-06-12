using './main.bicep'

// =============================================================================
// Demo parameters: one Windows Server 2025 VM on Azure Local.
//
// The admin password is read from the LOCALBOX_ADMIN_PASSWORD environment variable
// (never stored in the file). Export it before deploying:
//     export LOCALBOX_ADMIN_PASSWORD='<your-password>'
//
// Adjust hciLogicalNetworkName / customLocationName / imageName to match YOUR
// Azure Local instance. storagePathId is left empty (automatic high-availability
// placement); set it to a storage container resource ID to pin placement to a CSV.
// =============================================================================

param name = 'demo-ws2025-01'
param location = 'westeurope'
param vCPUCount = 2
param memoryMB = 8192
param adminUsername = 'arcdemo'
param adminPassword = readEnvironmentVariable('LOCALBOX_ADMIN_PASSWORD')

param imageName = '2025-datacenter-azure-edition-01'
param isMarketplaceImage = true

param hciLogicalNetworkName = 'localbox-vm-lnet-vlan200'
param customLocationName = 'jumpstart'
param storagePathId = ''

param dataDiskParams = [
  {
    name: 'demo-ws2025-01-data'
    diskSizeGB: 128
    dynamic: true
  }
]

// --- Optional AD domain join: uncomment and supply a domain password to enable. ---
// param domainToJoin = 'jumpstart.local'
// param domainJoinUserName = 'Administrator'
// param domainJoinPassword = readEnvironmentVariable('LOCALBOX_ADMIN_PASSWORD')
// param domainTargetOu = ''
