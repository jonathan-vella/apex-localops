// =============================================================================
// apex-localops — SFF profile. Nested-virtualization Hyper-V host.
//
// A Windows Server VM (nested-virt capable SKU) that builds the Azure Local SFF
// test VM INSIDE itself: it installs Hyper-V, configures an internal NAT+DHCP
// switch (HV-Internal-NAT), waits for the operator to stage the ROE ISO +
// Configurator App into the staging storage account, then creates a Generation 2
// nested VM with TPM on, Secure Boot off, >= 4 vCPU, 16 GB RAM, a 256 GB disk,
// boots the ROE Maintenance OS, and confirms "ROE setup completed successfully".
//
// Reached only over Azure Bastion (no public IP). The system-assigned identity is
// granted least privilege in main.bicep: Blob Data Reader on the staging SA, Key
// Vault Secrets Officer on the vault, and Tag Contributor on the resource group.
// =============================================================================

@description('The name of the Hyper-V host VM. Windows computer name limit is 15 characters.')
@maxLength(15)
param vmName string = 'LocalSFF-Host'

@description('The size of the host VM. Must be a nested-virtualization-capable SKU.')
@allowed([
  'Standard_D8s_v5'
  'Standard_D16s_v5'
  'Standard_E8s_v5'
  'Standard_E16s_v5'
  'Standard_D8s_v6'
  'Standard_D16s_v6'
  'Standard_E8s_v6'
  'Standard_E16s_v6'
])
param vmSize string = 'Standard_D8s_v5'

@description('Username for the Windows account.')
param windowsAdminUsername string = 'arcdemo'

@description('Password for the Windows account. 12-123 chars; 3 of lower/upper/number/special.')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('The Windows Server version (a fully patched image of this version is selected).')
param windowsOSVersion string = '2025-datacenter-g2'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Resource Id of the subnet in the virtual network.')
param subnetId string

@description('Choice to deploy Bastion to connect to the host VM (true => no public IP).')
param deployBastion bool = true

@description('Size of the single Premium data disk (drive V:) that holds the nested VHDX + ROE ISO.')
@minValue(256)
@maxValue(2048)
param dataDiskSizeGB int = 512

param resourceTags object

@description('Name of the staging storage account that holds the ROE ISO + Configurator App MSI.')
param stagingStorageAccountName string

@description('Name of the blob container holding the staged SFF artifacts.')
param stagingArtifactsContainer string = 'sff-artifacts'

@description('Name of the Key Vault used to store the ownership voucher.')
param keyVaultName string

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Base URL used to fetch the vendored artifacts/ tree from this repo.')
param templateBaseUrl string

@description('Enable automatic logon so the in-VM build resumes headless after the Hyper-V reboot.')
param vmAutologon bool = true

@description('Public DNS handed out by the internal Hyper-V DHCP scope.')
param natDNS string = '8.8.8.8'

// --- Nested SFF test VM geometry (passed through to the in-VM scripts) ---
@description('Name of the nested SFF test VM.')
param nestedVmName string = 'linuxsff-vm'

@description('Startup memory (MB) for the nested SFF test VM. The Learn doc specifies 16000.')
param nestedVmMemoryMB int = 16000

@description('Virtual processor count for the nested SFF test VM. Must be >= 4.')
@minValue(4)
param nestedVmCpuCount int = 4

@description('OS disk size (GB) for the nested SFF test VM. The Learn doc specifies 256.')
param nestedVmDiskGB int = 256

@description('Forces the bootstrap Custom Script Extension to re-run on each deployment. Defaults to a per-deployment timestamp; the bootstrap is idempotent so re-running is safe and lets a redeploy pick up a fixed script.')
param bootstrapForceUpdateTag string = utcNow()

@description('Name of the internal Hyper-V switch created on the host.')
param hvSwitchName string = 'HV-Internal-NAT'

@description('IPv4 CIDR for the internal Hyper-V NAT subnet.')
param hvSubnetPrefix string = '192.168.200.0/24'

@description('Host-side gateway IP on the internal Hyper-V switch.')
param hvGateway string = '192.168.200.1'

var encodedPassword = base64(windowsAdminPassword)
var publicIpAddressName = '${vmName}-PIP'
var networkInterfaceName = '${vmName}-NIC'
var osDiskType = 'Premium_LRS'
var dataDiskName = '${vmName}-DataDisk'

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

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (deployBastion == false) {
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

resource dataDisk 'Microsoft.Compute/disks@2023-04-02' = {
  name: dataDiskName
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGB
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
        diskSizeGB: 256
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
        version: 'latest'
      }
      dataDisks: [
        {
          lun: 0
          name: dataDiskName
          createOption: 'Attach'
          caching: 'None'
          managedDisk: {
            id: dataDisk.id
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

resource vmBootstrap 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'BootstrapSff'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    forceUpdateTag: bootstrapForceUpdateTag
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/sff/PowerShell/Bootstrap-Sff.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap-Sff.ps1 -adminUsername ${windowsAdminUsername} -adminPassword ${encodedPassword} -subscriptionId ${subscription().subscriptionId} -tenantId ${subscription().tenantId} -resourceGroup ${resourceGroup().name} -azureLocation ${location} -stagingStorageAccountName ${stagingStorageAccountName} -stagingContainer ${stagingArtifactsContainer} -keyVaultName ${keyVaultName} -workspaceName ${workspaceName} -templateBaseUrl ${templateBaseUrl} -vmAutologon ${vmAutologon} -natDNS ${natDNS} -hvSwitchName ${hvSwitchName} -hvSubnetPrefix ${hvSubnetPrefix} -hvGateway ${hvGateway} -nestedVmName ${nestedVmName} -nestedVmMemoryMB ${nestedVmMemoryMB} -nestedVmCpuCount ${nestedVmCpuCount} -nestedVmDiskGB ${nestedVmDiskGB}'
    }
  }
}

output adminUsername string = windowsAdminUsername
output hostVmName string = vm.name
output hostPrincipalId string = vm.identity.principalId
output publicIP string = deployBastion == false ? publicIpAddress!.properties.ipAddress : ''
