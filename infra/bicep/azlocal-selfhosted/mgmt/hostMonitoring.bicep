// Deploy host monitoring after both the workspace and VM exist. This module
// boundary avoids validating the DCR before Log Analytics initializes Event/Perf.

@description('Name of the existing cluster-host VM.')
param vmName string

@description('Name of the existing Log Analytics workspace.')
param workspaceName string

@description('Resource ID of the existing Log Analytics workspace.')
param workspaceResourceId string

@description('Azure region for monitoring resources.')
param location string

param resourceTags object

resource hostVm 'Microsoft.Compute/virtualMachines@2025-04-01' existing = {
  name: vmName
}

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

resource azureMonitorAgent 'Microsoft.Compute/virtualMachines/extensions@2025-04-01' = {
  parent: hostVm
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

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'apexlocal-host-dcra'
  scope: hostVm
  properties: {
    dataCollectionRuleId: dcr.id
  }
  dependsOn: [
    azureMonitorAgent
  ]
}

output dcrId string = dcr.id