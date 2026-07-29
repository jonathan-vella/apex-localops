// Runs the self-hosted bootstrap only after main.bicep has assigned host MI roles.

@description('Name of the existing cluster-host VM.')
param vmName string

@description('Azure region of the existing cluster-host VM.')
param location string

@description('Username for the host and nested local administrator accounts.')
param windowsAdminUsername string

@description('Password for the host and nested local administrator accounts.')
@secure()
param windowsAdminPassword string

@description('Name of the OAuth-only staging storage account.')
param stagingStorageAccountName string

@description('Name of the ISO staging container.')
param isoContainerName string = 'iso-images'

@description('Name of the private build-log container.')
param logsContainerName string = 'logs'

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Immutable raw-content base URL for the candidate or release artifact set.')
param templateBaseUrl string

@description('Immutable commit SHA or release tag used as the extension force-update value.')
param artifactRef string

@description('Name of the Azure Local instance.')
param clusterName string

@description('Deterministic suffix for cluster-owned Key Vault and diagnostics resources.')
param clusterResourceSuffix string

@description('Object ID of the Microsoft.AzureStackHCI resource provider service principal.')
param hciResourceProviderObjectId string

@description('Azure region the Azure Local instance and its Arc machines are created in. Must be an Azure Local supported region AND one your subscription is allowed to use: a restricted region fails Arc onboarding with RequestDisallowedByAzure 403 about ninety minutes into the build.')
param azureLocalInstanceLocation string = 'westeurope'

@description('Name of the lab Key Vault the host reads its own credential from on resume.')
param keyVaultName string

var encodedPassword = base64(windowsAdminPassword)

resource hostVm 'Microsoft.Compute/virtualMachines@2025-04-01' existing = {
  name: vmName
}

resource bootstrap 'Microsoft.Compute/virtualMachines/extensions@2025-04-01' = {
  parent: hostVm
  name: 'BootstrapApexLocal'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    forceUpdateTag: artifactRef
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/selfhosted/PowerShell/Bootstrap.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername ${windowsAdminUsername} -adminPassword ${encodedPassword} -subscriptionId ${subscription().subscriptionId} -tenantId ${subscription().tenantId} -resourceGroup ${resourceGroup().name} -azureLocation ${location} -stagingStorageAccountName ${stagingStorageAccountName} -isoContainerName ${isoContainerName} -logsContainerName ${logsContainerName} -workspaceName ${workspaceName} -templateBaseUrl ${templateBaseUrl} -vmAutologon true -clusterNodeCount 3 -nodeMemoryMB 98304 -nodeCpuCount 16 -clusterName ${clusterName} -clusterResourceSuffix ${clusterResourceSuffix} -azureLocalInstanceLocation ${azureLocalInstanceLocation} -hciResourceProviderObjectId ${hciResourceProviderObjectId} -keyVaultName ${keyVaultName}'
    }
  }
}

@description('Resource ID of the host bootstrap extension.')
output extensionId string = bootstrap.id
