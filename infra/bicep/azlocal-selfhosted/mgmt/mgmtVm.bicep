// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile. Management / acquisition jumpbox.
//
// A Windows Server 2025 VM on the workload subnet, reached over Azure Bastion (no
// public IP), egress via the subnet's NAT Gateway. This is the operator's "inside
// Azure" workstation for the one manual step in this profile: download the Azure
// Local OS ISO (Azure portal, license-gated) and the Windows Server ISO, then
// upload BOTH into the storage account's iso-images container (Upload-Isos.ps1).
//
// A system-assigned identity lets it authenticate to storage without keys
// (granted Storage Blob Data Contributor in main.bicep). The setup extension
// installs Azure CLI + Az PowerShell + AzCopy and stages Upload-Isos.ps1 with
// desktop instructions, because a stock image has none of that tooling.
// =============================================================================

@description('The name of the management VM. Windows computer name limit is 15 characters.')
@maxLength(15)
param vmName string = 'ApexLocal-Mgmt'

@description('The size of the management VM.')
param vmSize string = 'Standard_D4s_v5'

@description('Username for the local administrator account.')
param adminUsername string

@description('Password for the local administrator account. 12-123 chars; 3 of lower/upper/number/special.')
@minLength(12)
@maxLength(123)
@secure()
param adminPassword string

@description('Resource Id of the subnet to attach the management VM to (the workload subnet).')
param subnetId string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Windows Server version (a fully patched image of this version is selected).')
param windowsOSVersion string = '2025-datacenter-g2'

@description('Base URL used to fetch the helper scripts from this repo. Empty disables the jumpbox setup extension.')
param templateBaseUrl string = ''

@description('Name of the storage account that holds the staged ISOs (baked into the on-desktop upload instructions).')
param stagingStorageAccountName string = ''

@description('Name of the ISO blob container.')
param isoContainerName string = 'iso-images'

@description('Apply Windows Server Azure Hybrid Benefit (licenseType=Windows_Server). On by default; set false for license-included (PAYG).')
param enableAzureHybridBenefit bool = true

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
        // Generous OS disk: the operator downloads two multi-GB ISOs here before
        // uploading them to storage.
        diskSizeGB: 256
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
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

// Provision the jumpbox as an acquisition workstation: install Azure CLI + Az
// modules + AzCopy and stage Upload-Isos.ps1 + desktop instructions. Skipped when
// templateBaseUrl is empty (e.g. unit what-ifs).
resource jumpboxSetup 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = if (!empty(templateBaseUrl)) {
  parent: vm
  name: 'SetupJumpbox'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/selfhosted/PowerShell/Setup-Jumpbox.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Setup-Jumpbox.ps1 -templateBaseUrl ${templateBaseUrl} -stagingStorageAccountName ${stagingStorageAccountName} -isoContainerName ${isoContainerName}'
    }
  }
}

output managementVmName string = vm.name
output managementVmPrincipalId string = vm.identity.principalId
output managementVmPrivateIp string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
