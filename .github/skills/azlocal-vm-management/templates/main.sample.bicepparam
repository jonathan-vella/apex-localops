using './main.bicep'

// Example parameters for creating Azure Local VMs at scale.
// Customize the values to match your Azure Local instance, then deploy:
//   export AZLOCAL_VM_ADMIN_PASSWORD='<password>'
//   az deployment group create -g <rg> --template-file main.bicep --parameters main.sample.bicepparam

param location = 'eastus'
param customLocationName = 'cl-azlocal'
param logicalNetworkName = 'lnet-compute'
param imageName = 'winServer2022-01'
param isMarketplaceImage = true
param adminUsername = 'azureuser'

// Resolve the secret at deploy time from an environment variable — never commit it.
// The '' default keeps editors/no-secret builds clean; you MUST export the variable
// before deploying (an empty password is rejected by Azure Local).
param adminPassword = readEnvironmentVariable('AZLOCAL_VM_ADMIN_PASSWORD', '')

// Optional: pin VM placement to a specific storage path (CSV). Empty = automatic placement.
// param storagePathId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.AzureStackHCI/storageContainers/<name>'

// Optional: AD domain-join every VM (JsonADDomainExtension). Leave domainToJoin empty to skip.
// The VM's logical network must resolve the domain DNS/DC. The VM restarts after joining.
// param domainToJoin = 'contoso.local'
// param domainJoinUserName = 'domain-joiner'
// param domainJoinPassword = readEnvironmentVariable('AZLOCAL_VM_ADMIN_PASSWORD', '')
// param domainTargetOu = ''

// Add or remove entries to scale the batch up or down.
param vms = [
  {
    name: 'web-01'
    vCpuCount: 2
    memoryMB: 8192
  }
  {
    name: 'web-02'
    vCpuCount: 2
    memoryMB: 8192
  }
  {
    name: 'db-01'
    vCpuCount: 4
    memoryMB: 16384
    dataDisks: [
      {
        diskSizeGB: 256
        dynamic: true
      }
    ]
  }
]
