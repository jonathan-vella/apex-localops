// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile.
// Log Analytics workspace + a Data Collection Rule for cluster-host telemetry.
// The host VM runs the Azure Monitor Agent (wired in host.bicep) associated with
// this DCR, so the long headless in-VM build is diagnosable from Azure Monitor
// (Windows event logs + key perf counters) without Bastion/RDP. In-VM build logs
// also go to the storage 'logs' container (Send-ApexLogsToStorage).
// =============================================================================

@description('Name for the Log Analytics workspace.')
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

// Data Collection Rule: Windows event logs (System/Application, warning+) and a
// small set of perf counters, sent to the workspace. Associated with the host VM
// in host.bicep via the Azure Monitor Agent.
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${workspaceName}-host-dcr'
  location: location
  tags: resourceTags
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'eventLogs'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
      performanceCounters: [
        {
          name: 'perfCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\LogicalDisk(_Total)\\% Free Space'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'la'
        ]
      }
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'la'
        ]
      }
    ]
  }
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
output dcrId string = dcr.id
