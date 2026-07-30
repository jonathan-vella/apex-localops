// =============================================================================
// insights.bicep - Enable Azure Local cluster monitoring (the "Insights"
// components) by installing the Azure Monitor Agent (AMA) on each Arc-enabled
// cluster node and associating a Data Collection Rule (DCR) that streams Windows
// Event + performance data to the existing Log Analytics workspace.
//
// This replicates the portal "Enable Insights" flow (AMA + DCR + association)
// via IaC, per
// https://learn.microsoft.com/azure/azure-local/manage/monitor-single-23h2#enable-insights.
// The host-VM DCR (mgmt/hostMonitoring.bicep) covers only the physical host; this
// module covers the nested cluster NODES (apexlocal-n1/n2/n3).
// =============================================================================

@description('Names of the Arc-enabled Azure Local cluster nodes (Microsoft.HybridCompute/machines).')
param nodeNames array

@description('Name of the existing Log Analytics workspace.')
param workspaceName string

@description('Resource ID of the existing Log Analytics workspace.')
param workspaceResourceId string

@description('Azure region for the monitoring resources (the Azure Local instance region).')
param location string

@description('Resource tags.')
param resourceTags object = {}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${workspaceName}-cluster-dcr'
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
            '\\Network Interface(*)\\Bytes Total/sec'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la'
          workspaceResourceId: workspaceResourceId
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

resource nodes 'Microsoft.HybridCompute/machines@2025-01-13' existing = [
  for name in nodeNames: {
    name: name
  }
]

resource azureMonitorAgent 'Microsoft.HybridCompute/machines/extensions@2025-01-13' = [
  for (name, i) in nodeNames: {
    parent: nodes[i]
    name: 'AzureMonitorWindowsAgent'
    location: location
    properties: {
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorWindowsAgent'
      typeHandlerVersion: '1.0'
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
    }
  }
]

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [
  for (name, i) in nodeNames: {
    name: 'apexlocal-cluster-dcra'
    scope: nodes[i]
    properties: {
      dataCollectionRuleId: dcr.id
    }
    dependsOn: [
      azureMonitorAgent[i]
    ]
  }
]

@description('The cluster Insights DCR resource ID.')
output dcrId string = dcr.id
