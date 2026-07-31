// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile. Nested-virtualization cluster host.
//
// A large Windows Server 2025 VM that builds the ENTIRE Azure Local environment
// INSIDE itself with ZERO Jumpstart dependency:
//   1. Installs Hyper-V, pools the Premium data disks into V:, and creates an
//      internal switch + host NAT (192.168.1.0/24).
//   2. Waits for the operator to stage BOTH ISOs (Azure Local OS + Windows Server)
//      into the storage account, then pulls them with its MI.
//   3. Converts each ISO into a bootable Gen2 VHDX (ApexLocalOps/Convert-IsoToVhdx).
//   4. Builds a nested domain controller, then N nested Azure Local nodes, Arc-
//      registers the nodes, and runs the cluster validate -> deploy.
//
// Reached only over Azure Bastion (no public IP). The system-assigned identity is
// granted least privilege in main.bicep: Blob Data Contributor on the ISO storage
// (read ISOs + write logs), Tag Contributor on the RG (progress tags), and — for
// the in-VM cluster deploy, which performs role assignments — Contributor + User
// Access Administrator scoped to the resource group.
// =============================================================================

@description('The name of the cluster-host VM. Windows computer name limit is 15 characters.')
@maxLength(15)
param vmName string = 'ApexLocal-Host'

@description('The size of the host VM. Must be a nested-virtualization-capable, high-memory SKU.')
@allowed([
  'Standard_E64s_v6'
])
param vmSize string = 'Standard_E64s_v6'

@description('Username for the Windows account.')
param windowsAdminUsername string = 'arcdemo'

@description('Password for the Windows account. 12-123 chars; 3 of lower/upper/number/special.')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('The Windows Server version (a fully patched image of this version is selected).')
param windowsOSVersion string = '2025-datacenter-g2'

@description('Pinned Windows Server image version verified in Sweden Central and Germany West Central.')
param windowsImageVersion string = '26100.33158.260711'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Resource Id of the subnet in the virtual network.')
param subnetId string

@description('Choice to deploy Bastion to connect to the host VM (true => no public IP).')
param deployBastion bool = true

@description('Number of Premium data disks to pool into drive V: for nested storage.')
@allowed([
  8
])
param dataDiskCount int = 8

@description('Size (GB) of each Premium data disk. 1024 GB is natively P30.')
@allowed([
  1024
])
param dataDiskSizeGB int = 1024

@description('Performance tier for each data disk (P30 = 5000 IOPS / 200 MBps, the native tier at 1024 GB).')
param dataDiskTier string = 'P30'

@description('Apply Windows Server Azure Hybrid Benefit (licenseType=Windows_Server). On by default; set false for license-included (PAYG).')
param enableAzureHybridBenefit bool = true

param resourceTags object
var publicIpAddressName = '${vmName}-PIP'
var networkInterfaceName = '${vmName}-NIC'
var osDiskType = 'Premium_LRS'

resource networkInterface 'Microsoft.Network/networkInterfaces@2024-10-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: deployBastion == false
            ? {
                id: publicIpAddress.id
              }
            : null
        }
      }
    ]
  }
  tags: resourceTags
}

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2024-10-01' = if (deployBastion == false) {
  name: publicIpAddressName
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
  sku: {
    name: 'Standard'
  }
  tags: resourceTags
}

// Pool of Premium data disks. 1024 GB is the native P30 size, so the pinned tier costs nothing
// extra - the previous 256 GB disks were billed at the P30 tier anyway for the IOPS the nested
// Storage Spaces Direct pool needs, while giving a quarter of the capacity.
resource dataDisks 'Microsoft.Compute/disks@2025-01-02' = [
  for i in range(0, dataDiskCount): {
    name: '${vmName}-DataDisk-${i}'
    location: location
    sku: {
      name: 'Premium_LRS'
    }
    properties: {
      creationData: {
        createOption: 'Empty'
      }
      diskSizeGB: dataDiskSizeGB
      tier: dataDiskTier
    }
    tags: resourceTags
  }
]

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' = {
  name: vmName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    licenseType: enableAzureHybridBenefit ? 'Windows_Server' : null
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        name: '${vmName}-OSDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        diskSizeGB: 1024
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
        version: windowsImageVersion
      }
      dataDisks: [
        for i in range(0, dataDiskCount): {
          lun: i
          name: dataDisks[i].name
          createOption: 'Attach'
          caching: 'None'
          managedDisk: {
            id: dataDisks[i].id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: windowsAdminUsername
      adminPassword: windowsAdminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: false
      }
    }
  }
}

output adminUsername string = windowsAdminUsername
output hostVmName string = vm.name
output hostPrincipalId string = vm.identity.principalId
output publicIP string = deployBastion == false ? publicIpAddress!.properties.ipAddress : ''
