// =============================================================================
// apex-localops — SFF profile. Windows 11 management / acquisition jumpbox.
//
// Placed on the SFF workload subnet, reached over Azure Bastion (no public IP),
// egress via the subnet's NAT Gateway. This is the operator's "inside Azure"
// workstation for the one manual step: download the ROE ISO + Configurator App
// from the Azure portal, then upload them to the staging storage account
// (Publish-SffArtifacts.ps1). A system-assigned identity lets it authenticate to
// storage without keys (granted Storage Blob Data Contributor in main.bicep).
// TrustedLaunch (Secure Boot + vTPM) as required by Windows 11.
// =============================================================================

@description('The name of the management VM. Windows computer name limit is 15 characters.')
@maxLength(15)
param vmName string = 'LocalSFF-Mgmt'

@description('The size of the management VM.')
param vmSize string = 'Standard_D4s_v5'

@description('Username for the local administrator account.')
param adminUsername string

@description('Password for the local administrator account. Must be 12-123 characters and contain 3 of: lowercase, uppercase, number, special character.')
@minLength(12)
@maxLength(123)
@secure()
param adminPassword string

@description('Resource Id of the subnet to attach the management VM to (the SFF workload subnet).')
param subnetId string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Windows 11 marketplace image SKU (publisher microsoftwindowsdesktop, offer windows-11).')
param windows11Sku string = 'win11-24h2-pro'

@description('Base URL used to fetch the SFF helper scripts from this repo. Empty disables the jumpbox setup extension.')
param templateBaseUrl string = ''

@description('Name of the staging storage account (baked into the on-desktop upload instructions).')
param stagingStorageAccountName string = ''

@description('Name of the staging artifacts blob container.')
param stagingArtifactsContainer string = 'sff-artifacts'

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
output managementVmPrincipalId string = vm.identity.principalId
output managementVmPrivateIp string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress

// Provision the jumpbox as an acquisition workstation: install Azure CLI + Az modules and
// stage Publish-SffArtifacts.ps1 + desktop instructions. A stock Windows 11 image has none
// of this tooling, so without it the documented "upload from the jumpbox" path can't run.
// Skipped when templateBaseUrl is empty (e.g. unit what-ifs).
resource jumpboxSetup 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = if (!empty(templateBaseUrl)) {
  parent: vm
  name: 'SetupSffJumpbox'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/sff/PowerShell/Setup-SffJumpbox.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Setup-SffJumpbox.ps1 -templateBaseUrl ${templateBaseUrl} -stagingStorageAccountName ${stagingStorageAccountName} -stagingContainer ${stagingArtifactsContainer}'
    }
  }
}
