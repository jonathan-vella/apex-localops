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
