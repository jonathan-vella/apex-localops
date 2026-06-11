// =============================================================================
// apex-localops — SFF profile. Log Analytics workspace for host telemetry.
// =============================================================================

@description('Name for your Log Analytics workspace.')
param workspaceName string

@description('Azure region to deploy the Log Analytics workspace.')
param location string = resourceGroup().location

@description('SKU, leave default pergb2018.')
param sku string = 'pergb2018'

param resourceTags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: sku
    }
  }
  tags: resourceTags
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
