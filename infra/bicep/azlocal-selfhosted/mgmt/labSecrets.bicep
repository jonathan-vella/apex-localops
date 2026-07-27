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

@description('Object id of the operator or group that may read the secret. Empty skips the assignment.')
param operatorPrincipalId string = ''

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
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
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

output keyVaultName string = keyVault.name
