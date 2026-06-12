// =============================================================================
// AVD control plane for Azure Local session hosts.
//
// Deploys the AZURE-SIDE Azure Virtual Desktop objects (host pool, desktop
// application group, workspace). Session hosts themselves are Arc VMs created on
// the Azure Local cluster separately (Deploy-AzLocalWorkloads.ps1 -Stage avd-host).
//
// Management type = STANDARD (pooled). "Session host configuration" management is
// NOT supported on Azure Local, so we use standard management + breadth-first LB.
//
// Deployed by the OPERATOR from the dev container (not the VM managed identity):
//   az deployment group create -g <rg> \
//     --template-file infra/bicep/azlocal-js/avd/main.bicep \
//     --parameters infra/bicep/azlocal-js/avd/main.bicepparam
//
// The host-pool registration token is produced as an output (valid until
// registrationTokenExpiration); retrieve it to register the session host.
// =============================================================================

@description('Azure region for the AVD metadata (host pool/workspace/app group). Independent of where session hosts run.')
param location string = 'westeurope'

@description('Host pool name.')
param hostPoolName string = 'azl-hp01'

@description('Desktop application group name.')
param appGroupName string = 'azl-dag01'

@description('Workspace name.')
param workspaceName string = 'azl-ws01'

@description('Friendly name shown to users in the workspace.')
param workspaceFriendlyName string = 'Azure Local Desktops'

@description('Max sessions per pooled session host.')
param maxSessionLimit int = 5

@description('Token validity in hours from deployment time (1-720). The registration token is generated at deploy time.')
@minValue(1)
@maxValue(720)
param tokenValidityHours int = 24

@description('Deployment timestamp - do not set explicitly; used to compute the registration-token expiry. utcNow() is only valid as a param default.')
param baseTime string = utcNow('u')

@description('Resource tags.')
param tags object = {
  Project: 'jumpstart_LocalBox'
  Workload: 'AVD'
}

// Registration token expiration must be an absolute time; derive from deployment time.
var tokenExpiration = dateTimeAdd(baseTime, 'PT${tokenValidityHours}H')

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2025-10-10' = {
  name: hostPoolName
  location: location
  tags: tags
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'Desktop'
    maxSessionLimit: maxSessionLimit
    startVMOnConnect: false
    validationEnvironment: false
    registrationInfo: {
      expirationTime: tokenExpiration
      registrationTokenOperation: 'Update'
    }
  }
}

resource appGroup 'Microsoft.DesktopVirtualization/applicationGroups@2025-10-10' = {
  name: appGroupName
  location: location
  tags: tags
  properties: {
    hostPoolArmPath: hostPool.id
    applicationGroupType: 'Desktop'
    friendlyName: 'Session Desktop'
  }
}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2025-10-10' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    friendlyName: workspaceFriendlyName
    applicationGroupReferences: [
      appGroup.id
    ]
  }
}

@description('Host pool resource name (use with `az desktopvirtualization hostpool` to (re)generate the registration token).')
output hostPoolName string = hostPool.name

@description('The AVD host-pool registration token. Feed this to Deploy-AzLocalWorkloads.ps1 -Stage avd-host -RegistrationToken <token>.')
@secure()
output registrationToken string = hostPool.properties.registrationInfo.token

@description('Token expiration (UTC).')
output registrationTokenExpiration string = tokenExpiration

output workspaceName string = workspace.name
output appGroupName string = appGroup.name
