// =============================================================================
// apex-localops — SFF profile. Staging storage account.
//
// Holds the Microsoft-owned artifacts the SFF host needs but which CANNOT be
// vendored into this repo (portal/subscription-gated, multi-GB): the Maintenance
// OS (ROE) ISO and the Configurator App MSI. Per the project's "all downloads
// initiated from Azure resources" rule, an operator stages these two files into
// the `sff-artifacts` container FROM an Azure resource (the Bastion jumpbox or
// Azure Cloud Shell). The host then pulls them with its managed identity.
//
// Hardened: no public blob access, HTTPS-only, TLS1.2 minimum, container ACL None.
// =============================================================================

@description('Storage Account type.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Globally unique storage account name (3-24 lowercase alphanumerics).')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'localsff${uniqueString(resourceGroup().id)}'

@description('Name of the blob container that holds the staged SFF artifacts (ROE ISO + Configurator App MSI).')
param stagingArtifactsContainer string = 'sff-artifacts'

param resourceTags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
  }
  tags: resourceTags
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource artifactsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: stagingArtifactsContainer
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output stagingArtifactsContainer string = artifactsContainer.name
