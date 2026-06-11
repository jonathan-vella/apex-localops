// =============================================================================
// JS-LOCAL CUSTOMIZATION — not part of upstream microsoft/azure_arc LocalBox.
// A Windows 11 management/jumpbox VM placed on the LocalBox workload subnet.
// - No public IP: reached over Azure Bastion (deployBastion = true).
// - Outbound egress via the subnet's NAT Gateway (created when Bastion is on).
// - TrustedLaunch (Secure Boot + vTPM) as required by Windows 11.
// =============================================================================

@description('The name of the management VM. Windows computer name limit is 15 characters.')
@maxLength(15)
param vmName string = 'LocalBox-Mgmt'

@description('The size of the management VM.')
param vmSize string = 'Standard_D4s_v5'

@description('Username for the local administrator account.')
param adminUsername string

@description('Password for the local administrator account. Must be 12-123 characters and contain 3 of: lowercase, uppercase, number, special character.')
@minLength(12)
@maxLength(123)
@secure()
param adminPassword string

@description('Resource Id of the subnet to attach the management VM to (the LocalBox workload subnet).')
param subnetId string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Windows 11 marketplace image SKU (publisher microsoftwindowsdesktop, offer windows-11).')
param windows11Sku string = 'win11-24h2-pro'

param resourceTags object

var networkInterfaceName = '${vmName}-NIC'
var osDiskType = 'Premium_LRS'

resource networkInterface 'Microsoft.Network/networkInterfaces@2024-07-01' = {
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
        }
      }
    ]
  }
  tags: resourceTags
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Azure Hybrid Benefit for Windows client (requires eligible Windows 10/11 E3/E5 or
    // Windows VDA per-user licenses with multi-tenant hosting rights).
    licenseType: 'Windows_Client'
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
      }
      imageReference: {
        publisher: 'microsoftwindowsdesktop'
        offer: 'windows-11'
        sku: windows11Sku
        version: 'latest'
      }
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
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
  }
}

output managementVmName string = vm.name
output managementVmPrivateIp string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
