// =============================================================================
// apex-localops — self-hosted profile. Key Vault for the lab admin credential.
//
// The build scrubs APEX_AdminPasswordB64 from the host whenever it fails, so the
// credential is never left sitting on an idle machine. Without somewhere to keep
// it, every resume forces the operator to retype the password by hand, which is
// exactly the manual step this lab is meant to avoid. Storing it here lets
// resume-selfhosted.sh and recover-selfhosted.sh fetch it with the operator's own
// Azure identity instead.
//
// RBAC-authorization mode is used: writing the secret from this template is a
// control-plane operation available to the deployer, while reading it later needs
// an explicit Key Vault Secrets User assignment.
// =============================================================================

@description('Name of the Key Vault. 3-24 lowercase alphanumerics/hyphens; globally unique.')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'apexkv${uniqueString(resourceGroup().id)}'

@description('Location for the Key Vault.')
param location string = resourceGroup().location

@description('Azure AD tenant id that the Key Vault belongs to.')
param tenantId string = subscription().tenantId

param resourceTags object

@description('Lab admin password to store so resume and recover need no retyping.')
@secure()
param adminPassword string

@description('Object id of the operator or group that may read the secret. Empty skips the assignment. Reaching the vault needs a session inside the virtual network, such as the jumpbox over Bastion.')
param operatorPrincipalId string = ''

@description('Resource ID of the workload subnet the private endpoint is placed in.')
param subnetId string

@description('Resource ID of the virtual network linked to the Key Vault private DNS zone.')
param virtualNetworkId string

@description('Enable purge protection. OFF by default so cleanup-selfhosted.sh can purge the vault and redeploy under the same resource-group name.')
param enablePurgeProtection bool = false

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Purge protection cannot be disabled once enabled, and an explicit 'false'
    // is rejected by the API, so omit the property (null) when off.
    enablePurgeProtection: enablePurgeProtection ? true : null
    // Public access is denied by policy in the target subscriptions, and a vault
    // that requests it is silently flipped to Disabled with its ACLs dropped, so
    // the private endpoint below is the only route to the secret.
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
      ipRules: []
      virtualNetworkRules: []
    }
  }
  tags: resourceTags
}

resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: keyVault
  name: 'lab-admin-password'
  properties: {
    value: adminPassword
    contentType: 'Self-hosted lab admin password; delete the resource group to destroy it.'
  }
}

resource operatorSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(operatorPrincipalId)) {
  name: guid(keyVault.id, operatorPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: operatorPrincipalId
  }
}

resource vaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-10-01' = {
  name: '${keyVaultName}-vault-pe'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  tags: resourceTags
}

resource vaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: resourceTags
}

resource vaultPrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: vaultPrivateDnsZone
  name: '${keyVaultName}-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
  tags: resourceTags
}

resource vaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-10-01' = {
  parent: vaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: vaultPrivateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    vaultPrivateDnsVnetLink
  ]
}

output keyVaultName string = keyVault.name
output keyVaultPrivateEndpointId string = vaultPrivateEndpoint.id
