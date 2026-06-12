using './main.bicep'

// AVD control-plane parameters. Metadata region is independent of where the
// session hosts physically run (the Azure Local cluster in westeurope).
param location = 'westeurope'
param hostPoolName = 'azl-hp01'
param appGroupName = 'azl-dag01'
param workspaceName = 'azl-ws01'
param workspaceFriendlyName = 'Azure Local Desktops'
param maxSessionLimit = 5
param tokenValidityHours = 24
