// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile.
// Log Analytics workspace for cluster-host + jumpbox telemetry and build logs.
// =============================================================================

@description('Name for the Log Analytics workspace.')
param workspaceName string

@description('Azure region to deploy the Log Analytics workspace.')
param location string = resourceGroup().location

@description('SKU, leave default pergb2018.')
param sku string = 'pergb2018'

param resourceTags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
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
output workspaceCustomerId string = workspace.properties.customerId
