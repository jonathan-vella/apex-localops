// =============================================================================
// apex-localops — SFF profile. Key Vault for the ownership voucher.
//
// The SFF "ownership voucher" (.pem) proves device ownership during Azure Arc
// machine provisioning. After the operator downloads it from the nested VM via
// the Configurator App (a guided, host-side step), the host helper stores it
// here as a base64 secret. RBAC-authorization mode is used so the host managed
// identity (Key Vault Secrets Officer) can write it and operators (Key Vault
// Secrets User, via the Entra operator group) can read it later.
// =============================================================================

@description('Name of the Key Vault. 3-24 lowercase alphanumerics/hyphens; globally unique.')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'sffkv${uniqueString(resourceGroup().id)}'

@description('Location for the Key Vault.')
param location string = resourceGroup().location

@description('Azure AD tenant id that the Key Vault belongs to.')
param tenantId string = subscription().tenantId

param resourceTags object

@description('Enable Key Vault purge protection. OFF by default so the SFF demo can be fully torn down (cleanup-sff.sh purges the vault) and redeployed with the same resource-group name. Enable only if you must guarantee voucher-secret retention.')
param enablePurgeProtection bool = false

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
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
    // Only set the property when enabling: purge protection cannot be disabled once on,
    // and an explicit 'false' is rejected by the API, so omit it (null) when off.
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  tags: resourceTags
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
