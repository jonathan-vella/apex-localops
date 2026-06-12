// Azure Local Arc VM — single-VM module.
// Invoked once per VM by main.bicep to create Azure Local VMs at scale.
//
// Mirrors the Microsoft sample (Bicep tab):
// https://learn.microsoft.com/azure/azure-local/manage/create-arc-virtual-machines?tabs=biceptemplate
// Grounded copy: docs/upstream/azure-local/manage/create-arc-virtual-machines.md
//
// Each VM is composed of: an Arc HybridCompute machine (zero-touch onboarding) +
// a network interface + optional data disks + a virtualMachineInstance scoped to
// the machine. The instance name MUST be 'default' (one VM instance per machine).

@description('Optional. Size of the data disk in GB.')
type dataDiskType = {
  @description('Size of the data disk in GB.')
  diskSizeGB: int

  @description('Optional. True for a dynamically expanding disk.')
  dynamic: bool?
}

@description('VM name. Also used as the Arc machine name and guest computer name. Windows: <= 15 chars.')
@maxLength(15)
param name string

@description('Azure region of the Azure Local instance resources.')
param location string

@description('Virtual processor count assigned to the VM.')
param vCpuCount int = 2

@description('Memory assigned to the VM, in MB.')
param memoryMB int = 8192

@description('Local administrator username for the guest OS.')
param adminUsername string

@secure()
@description('Local administrator password for the guest OS.')
param adminPassword string

@description('Name of an existing VM image on the Azure Local instance. Example: winServer2022-01.')
param imageName string

@description('Set true when imageName is an Azure Marketplace gallery image; false for a custom gallery image.')
param isMarketplaceImage bool = true

@description('Name of an existing logical network on the Azure Local instance. Example: lnet-compute.')
param logicalNetworkName string

@description('Name of the custom location for the Azure Local instance (from the instance Overview blade).')
param customLocationName string

@description('Data disks to attach. Empty array = OS disk only.')
param dataDisks dataDiskType[] = []

var nicName = 'nic-${name}'
var customLocationId = resourceId('Microsoft.ExtendedLocation/customLocations', customLocationName)
var imageId = isMarketplaceImage
  ? resourceId('Microsoft.AzureStackHCI/marketplaceGalleryImages', imageName)
  : resourceId('Microsoft.AzureStackHCI/galleryImages', imageName)
var logicalNetworkId = resourceId('Microsoft.AzureStackHCI/logicalNetworks', logicalNetworkName)

// Pre-create an Arc-connected machine with a system-assigned identity. This enables
// zero-touch onboarding of the Arc VM during deployment.
resource hybridComputeMachine 'Microsoft.HybridCompute/machines@2023-10-03-preview' = {
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
          // Uncomment to pin a static IP; otherwise an address is allocated from
          // the logical network's pool or via DHCP.
          // privateIPAddress: 'x.x.x.x'
          subnet: {
            id: logicalNetworkId
          }
        }
      }
    ]
  }
}

resource dataDisk 'Microsoft.AzureStackHCI/virtualHardDisks@2024-01-01' = [
  for (disk, i) in dataDisks: {
    name: '${name}-datadisk-${padLeft(i + 1, 2, '0')}'
    location: location
    extendedLocation: {
      type: 'CustomLocation'
      name: customLocationId
    }
    properties: {
      diskSizeGB: disk.diskSizeGB
      dynamic: disk.?dynamic
    }
  }
]

resource virtualMachine 'Microsoft.AzureStackHCI/virtualMachineInstances@2024-01-01' = {
  name: 'default' // Must be 'default' — exactly one VM instance per Arc machine.
  scope: hybridComputeMachine
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Custom'
      processors: vCpuCount
      memoryMB: memoryMB
    }
    osProfile: {
      adminUsername: adminUsername
      adminPassword: adminPassword
      computerName: name
      // For a Linux image, replace windowsConfiguration with linuxConfiguration.
      windowsConfiguration: {
        provisionVMAgent: true
        provisionVMConfigAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        id: imageId
      }
      dataDisks: [
        for (disk, i) in dataDisks: {
          id: dataDisk[i].id
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
}

@description('The VM name.')
output vmName string = name

@description('The full resource ID of the VM instance.')
output vmResourceId string = virtualMachine.id
