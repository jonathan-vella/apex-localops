// Prepares the acquisition jumpbox only after main.bicep grants its MI blob access.

@description('Name of the existing management jumpbox VM.')
param vmName string

@description('Azure region of the existing management jumpbox VM.')
param location string

@description('Immutable raw-content base URL for the candidate or release artifact set.')
param templateBaseUrl string

@description('Immutable commit SHA or release tag used as the extension force-update value.')
param artifactRef string

@description('Name of the OAuth-only staging storage account.')
param stagingStorageAccountName string

@description('Name of the ISO staging container.')
param isoContainerName string = 'iso-images'

resource managementVm 'Microsoft.Compute/virtualMachines@2025-04-01' existing = {
  name: vmName
}

resource setup 'Microsoft.Compute/virtualMachines/extensions@2025-04-01' = {
  parent: managementVm
  name: 'SetupJumpbox'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    forceUpdateTag: artifactRef
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/selfhosted/PowerShell/Setup-Jumpbox.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Setup-Jumpbox.ps1 -templateBaseUrl ${templateBaseUrl} -stagingStorageAccountName ${stagingStorageAccountName} -isoContainerName ${isoContainerName}'
    }
  }
}

@description('Resource ID of the jumpbox setup extension.')
output extensionId string = setup.id
