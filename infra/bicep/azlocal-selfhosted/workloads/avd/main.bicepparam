using './main.bicep'

// AVD control plane for the self-hosted Azure Local cluster. Metadata region is
// independent of where the session hosts run (canadacentral, matching the instance).
param location = 'canadacentral'
param hostPoolName = 'apexlocal-hp01'
param appGroupName = 'apexlocal-dag01'
param workspaceName = 'apexlocal-ws01'
param workspaceFriendlyName = 'Apex Local Desktops'
param maxSessionLimit = 5
param tokenValidityHours = 24
