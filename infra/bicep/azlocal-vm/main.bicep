// =============================================================================
// main.bicep - Deploy ONE Windows Server 2025 VM on Azure Local (Arc) using Bicep.
//
// Standalone demo template. Deploys, in dependency order:
//   1. Microsoft.HybridCompute/machines      - the Arc machine (SystemAssigned identity,
//                                               for zero-touch guest-agent onboarding)
//   2. Microsoft.AzureStackHCI/networkInterfaces - a NIC on an existing logical network
//   3. Microsoft.AzureStackHCI/virtualHardDisks  - optional data disks
//   4. Microsoft.AzureStackHCI/virtualMachineInstances - the sized VM ('default')
//   5. Microsoft.HybridCompute/machines/extensions     - optional AD domain join
//
// WHY THE hardwareProfile MATTERS: Azure Local sizes a VM via
//   hardwareProfile = { vmSize: 'Custom', processors: <n>, memoryMB: <mb> }
// You MUST set vmSize:'Custom'. Omitting it (or using an Azure VM SKU name like
// Standard_D2s_v3 via the CLI) yields an unbootable 0-CPU / 0-MB VM whose guest agent
// never installs. This template always sets vmSize:'Custom'.
//
// API versions are the latest GA: AzureStackHCI types 2024-01-01; HybridCompute 2025-01-13.
//
// Adapted from the Microsoft canonical sample https://aka.ms/hci-vmbiceptemplate
// (azure-quickstart-templates / microsoft.azurestackhci / vm-windows-disks-and-adjoin).
// =============================================================================

@maxLength(15)
@description('VM name (also the computer name; <= 15 chars for NetBIOS / domain join).')
param name string = 'demo-ws2025-01'

@description('Azure region of the Azure Local instance (for example: westeurope).')
param location string = resourceGroup().location

@minValue(1)
@maxValue(2048)
@description('Number of virtual processors (CPU cores).')
param vCPUCount int = 2

@minValue(512)
@description('Memory in MB. Must be a multiple of 4 (for example: 8192 = 8 GB).')
param memoryMB int = 8192

@description('In-guest local administrator username.')
param adminUsername string = 'arcdemo'

@secure()
@description('In-guest local administrator password (supply via readEnvironmentVariable in the .bicepparam).')
param adminPassword string

@description('Gallery image resource name already present on the cluster (for example: 2025-datacenter-azure-edition-01).')
param imageName string

@description('Set true if the referenced image is an Azure Marketplace gallery image (false = custom gallery image).')
param isMarketplaceImage bool = true

@description('Name of an existing logical network on the cluster (for example: localbox-vm-lnet-vlan200).')
param hciLogicalNetworkName string

@description('Name of the custom location for the Azure Local instance (for example: jumpstart).')
param customLocationName string

@description('Storage path (CSV) resource ID for the VM config + non-OS disks. Empty = automatic high-availability path.')
param storagePathId string = ''

@description('Data disks to create and attach. Provide [] for none.')
param dataDiskParams dataDiskArrayType = []

// --- Optional AD domain join (JsonADDomainExtension). Leave domainToJoin empty to skip. ---
@description('AD domain FQDN to join (for example: jumpstart.local). Empty = no domain join.')
param domainToJoin string = ''

@description('Optional OU path (for example: ou=computers,dc=jumpstart,dc=local).')
param domainTargetOu string = ''

@description('Domain-join username WITHOUT the domain prefix (for example: Administrator). Required if domainToJoin is set.')
param domainJoinUserName string = ''

@secure()
@description('Password for the domain-join user. Required if domainToJoin is set.')
param domainJoinPassword string = ''

type dataDiskType = {
  @description('Disk resource name.')
  name: string
  @description('Disk size in GB.')
  diskSizeGB: int
  @description('Dynamic (expanding) disk. Optional.')
  dynamic: bool?
}
type dataDiskArrayType = dataDiskType[]

var nicName = '${name}-nic'
var customLocationId = resourceId('Microsoft.ExtendedLocation/customLocations', customLocationName)
var imageId = isMarketplaceImage
  ? resourceId('Microsoft.AzureStackHCI/marketplaceGalleryImages', imageName)
  : resourceId('Microsoft.AzureStackHCI/galleryImages', imageName)
var logicalNetworkId = resourceId('Microsoft.AzureStackHCI/logicalNetworks', hciLogicalNetworkName)

// Pre-create the Arc Connected Machine (with identity) for zero-touch onboarding of the VM.
resource hybridComputeMachine 'Microsoft.HybridCompute/machines@2025-01-13' = {
  name: name
  location: location
  kind: 'HCI'
  identity: {
    type: 'SystemAssigned'
  }
}

resource nic 'Microsoft.AzureStackHCI/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          // Omit privateIPAddress to auto-allocate from the logical network's IP pool / DHCP.
          subnet: {
            id: logicalNetworkId
          }
        }
      }
    ]
  }
}

resource dataDisks 'Microsoft.AzureStackHCI/virtualHardDisks@2024-01-01' = [
  for disk in dataDiskParams: {
    name: disk.name
    location: location
    extendedLocation: {
      type: 'CustomLocation'
      name: customLocationId
    }
    properties: {
      diskSizeGB: disk.diskSizeGB
      dynamic: disk.?dynamic
      containerId: empty(storagePathId) ? null : storagePathId
    }
  }
]

resource virtualMachine 'Microsoft.AzureStackHCI/virtualMachineInstances@2024-01-01' = {
  name: 'default' // value MUST be 'default'
  scope: hybridComputeMachine
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Custom' // REQUIRED so processors/memoryMB are honored (omitting this yields 0/0)
      processors: vCPUCount
      memoryMB: memoryMB
    }
    osProfile: {
      adminUsername: adminUsername
      adminPassword: adminPassword
      computerName: name
      windowsConfiguration: {
        provisionVMAgent: true // moc guest agent
        provisionVMConfigAgent: true // Azure Arc connected machine agent
      }
    }
    storageProfile: {
      vmConfigStoragePathId: empty(storagePathId) ? null : storagePathId
      imageReference: {
        id: imageId
      }
      dataDisks: [
        for disk in dataDiskParams: {
          id: resourceId('Microsoft.AzureStackHCI/virtualHardDisks', disk.name)
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
  dependsOn: [
    dataDisks
  ]
}

// Optional declarative AD domain join (only when domainToJoin is provided).
resource domainJoin 'Microsoft.HybridCompute/machines/extensions@2025-01-13' = if (!empty(domainToJoin)) {
  parent: hybridComputeMachine
  location: location
  name: 'domainJoinExtension'
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      name: domainToJoin
      OUPath: domainTargetOu
      User: '${domainToJoin}\\${domainJoinUserName}'
      Restart: true
      Options: 3
    }
    protectedSettings: {
      Password: domainJoinPassword
    }
  }
  dependsOn: [
    virtualMachine
  ]
}

@description('The VM (computer) name.')
output vmName string = name

@description('The Azure Local VM instance resource ID.')
output vmInstanceId string = virtualMachine.id

@description('The Arc machine resource ID.')
output machineId string = hybridComputeMachine.id
