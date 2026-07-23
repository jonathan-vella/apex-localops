// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile. ISO staging storage account.
//
// Holds the two Microsoft-owned base images this profile needs but which CANNOT
// be vendored into the repo (portal/eval gated, multi-GB): the Azure Local OS
// ISO and the Windows Server ISO. Per the project's "all downloads initiated
// from an Azure resource" rule, the operator downloads both ISOs ON THE JUMPBOX
// (reached over Bastion) and uploads them into the `iso-images` container with
// Upload-Isos.ps1. The cluster host then pulls both with its managed identity.
//
// A second `logs` container receives the in-VM build logs the host uploads back.
//
// Hardened: no public blob access, HTTPS-only, TLS1.2 minimum, container ACL None.
//
// RBAC is assigned by the parent (main.bicep), not here, because the principals
// (deployer + the two VM managed identities) are resolved at the orchestration
// layer. This module only emits the names/ids those assignments scope to.
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
param storageAccountName string

@description('Name of the blob container that holds the two staged ISOs (Azure Local OS + Windows Server).')
param isoContainerName string = 'iso-images'

@description('Name of the blob container the cluster host uploads its build logs into.')
param logsContainerName string = 'logs'

@description('Resource ID of the workload subnet used by the host and jumpbox.')
param subnetId string

@description('Resource ID of the virtual network linked to the Blob private DNS zone.')
param virtualNetworkId string

param resourceTags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
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
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
  tags: resourceTags
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2026-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource isoContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: blobService
  name: isoContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource logsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: blobService
  name: logsContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-10-01' = {
  name: '${storageAccountName}-blob-pe'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'blob'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  tags: resourceTags
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: resourceTags
}

resource blobPrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: '${storageAccountName}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
  tags: resourceTags
}

resource blobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-10-01' = {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    blobPrivateDnsVnetLink
  ]
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output isoContainerName string = isoContainer.name
output logsContainerName string = logsContainer.name
output blobPrivateEndpointId string = blobPrivateEndpoint.id
