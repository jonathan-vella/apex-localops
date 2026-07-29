// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile · orchestrator.
//
// Stands up a clean-room, ZERO-Jumpstart Azure Local lab in a Bastion-only,
// NAT-gatewayed resource group:
//   • a hardened storage account holding the two operator-staged ISOs,
//   • a Windows Server 2025 jumpbox (the in-Azure workstation for staging ISOs),
//   • a large nested-virtualization cluster host that builds a nested router VM,
//     a domain controller, and a 3-node Azure Local cluster entirely from those
//     ISOs (the router VM is the management subnet's gateway, Jumpstart-style),
//   • a Log Analytics workspace, Bastion, and NAT Gateway.
//
// The nested router VM (built inside the cluster host by ApexLocalOps) is the
// management subnet's gateway; the Azure jumpbox is the operator's workstation
// for the one manual step (download the two ISOs, upload them to the storage
// account). The cluster host pulls the ISOs with its managed identity.
//
// Public-safe by construction: NO tenant GUIDs and NO secrets are committed.
// scripts/deploy-selfhosted.sh resolves the deployer object id + the Azure Local
// RP object id at deploy time and reads the Windows password from
// LOCALSELF_ADMIN_PASSWORD via readEnvironmentVariable().
//
// RBAC (assigned here so all principals resolve at the orchestration layer):
//   • host VM identity      -> Storage Blob Data Contributor on the ISO storage
//                              + Contributor + User Access Administrator on the RG
//                                (the in-VM Azure Local cluster deploy performs
//                                 role assignments, so it needs UAA — Storage
//                                 data roles alone are NOT sufficient).
//   • jumpbox VM identity   -> Storage Blob Data Contributor on the ISO storage
// =============================================================================

@description('Username for the Windows accounts (cluster host + jumpbox + nested VMs).')
param windowsAdminUsername string = 'arcdemo'

@description('Password for the Windows accounts. 12-123 chars; 3 of lower/upper/number/special.')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('Location to deploy all infrastructure resources. Sweden Central is primary; Germany West Central is the explicit fallback.')
@allowed([
  'swedencentral'
  'germanywestcentral'
])
param location string = 'swedencentral'

@description('Resource-name prefix for the self-hosted resources.')
param namePrefix string = 'ApexLocal'

@description('Name for the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'ApexLocal-Workspace'

@description('Apply Azure Hybrid Benefit (Windows_Server) across both VMs. Set false for license-included (PAYG).')
param enableAzureHybridBenefit bool = true

@description('Deploy Azure Bastion (true => no public IP on any VM; NAT Gateway egress).')
param deployBastion bool = true

@description('Deploy the Windows Server 2025 acquisition / management jumpbox.')
param deployManagementVm bool = true

@description('Size of the management jumpbox.')
param managementVmSize string = 'Standard_D4s_v5'

@description('Name of the Azure Local instance (cluster) resource created in Azure. 3-15 chars for the pinned create-cluster contract.')
@minLength(3)
@maxLength(15)
param clusterName string = 'apexlocal'

// --- Artifact source (self-hosted in this repo) ---
@description('GitHub account that hosts this repository and its artifacts/ tree.')
param githubAccount string = 'jonathan-vella'

@description('GitHub repository name that hosts the vendored artifacts/ tree.')
param githubRepo string = 'apex-localops'

@description('Immutable Git commit SHA or release tag used for runtime artifacts.')
param artifactRef string = 'v1.3.0-rc.1'

@description('Name of the ISO blob container.')
param isoContainerName string = 'iso-images'

@description('Name of the build-logs blob container.')
param logsContainerName string = 'logs'

@description('Object id of the Azure Local Resource Provider service principal (app 1412d89f-b8a8-4111-b4fd-e82905cbd85d) in this tenant. Required by the in-VM cluster deploy; resolved at deploy time by scripts/deploy-selfhosted.sh.')
param hciResourceProviderObjectId string = ''

@description('Add CostControl/SecurityControl tags (Microsoft-internal lab tenants only).')
param governResourceTags bool = false

@description('Azure region the Azure Local instance and its Arc machines are created in. Restricted to Azure Local regions where the Arc Resource Bridge extension type microsoft.hybridaksoperator is also registered: a region that supports Azure Local but not that extension passes validation and then fails the ARB step about three hours into the deployment. Your subscription must also be permitted to create resources there: a restricted region fails Arc onboarding with a RequestDisallowedByAzure 403 roughly ninety minutes into the build.')
@allowed([
  'australiaeast'
  'canadacentral'
  'centralindia'
  'eastus'
  'japaneast'
  'southcentralus'
  'southeastasia'
  'uksouth'
  'westeurope'
])
param azureLocalInstanceLocation string = 'westeurope'

@description('Object id of the operator or group allowed to read the stored lab password, so resume and recover need no retyping. Resolved at deploy time by scripts/deploy-selfhosted.sh; empty skips the assignment.')
param operatorPrincipalId string = ''

@description('Tags applied to all resources.')
param tags object = {
  Project: 'apex_localselfhosted'
}

var resourceTags = governResourceTags
  ? union(tags, {
      CostControl: 'Ignore'
      SecurityControl: 'Ignore'
    })
  : tags

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/${githubRepo}/${artifactRef}/'
var hostVmSize = 'Standard_E64s_v6'
var hostDataDiskCount = 12
var hostDataDiskSizeGB = 256

// Deterministic resource names (calculable at the start of the deployment) so that
// resource-scoped role-assignment names/scopes don't depend on runtime module outputs.
var stagingStorageAccountName = 'apexloc${uniqueString(resourceGroup().id)}'
var labKeyVaultName = 'apexkv${uniqueString(resourceGroup().id)}'
var clusterResourceSuffix = take(uniqueString(resourceGroup().id, clusterName), 6)
var hostVmNameVar = '${namePrefix}-Host'
var managementVmNameVar = '${namePrefix}-Mgmt'
var hostVmResourceId = resourceId('Microsoft.Compute/virtualMachines', hostVmNameVar)
var managementVmResourceId = resourceId('Microsoft.Compute/virtualMachines', managementVmNameVar)

// Built-in role definition IDs.
var roleStorageBlobDataContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)
var roleKeyVaultSecretsUser = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)
var roleContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b24988ac-6180-42a0-ab88-20f7382dd24c'
)
var roleUserAccessAdministrator = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
)

module mgmtArtifactsDeployment 'mgmt/mgmtArtifacts.bicep' = {
  name: 'mgmtArtifactsDeployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    resourceTags: resourceTags
  }
}

module networkDeployment 'network/network.bicep' = {
  name: 'networkDeployment'
  params: {
    namePrefix: namePrefix
    deployBastion: deployBastion
    location: location
    resourceTags: resourceTags
  }
}

module labSecretsDeployment 'mgmt/labSecrets.bicep' = {
  name: 'labSecretsDeployment'
  params: {
    location: location
    keyVaultName: labKeyVaultName
    resourceTags: resourceTags
    adminPassword: windowsAdminPassword
    operatorPrincipalId: operatorPrincipalId
    subnetId: networkDeployment.outputs.subnetId
    virtualNetworkId: networkDeployment.outputs.vnetId
  }
}

module stagingStorageDeployment 'mgmt/stagingStorage.bicep' = {
  name: 'stagingStorageDeployment'
  params: {
    location: location
    storageAccountName: stagingStorageAccountName
    isoContainerName: isoContainerName
    logsContainerName: logsContainerName
    subnetId: networkDeployment.outputs.subnetId
    virtualNetworkId: networkDeployment.outputs.vnetId
    resourceTags: resourceTags
  }
}

module hostDeployment 'host/host.bicep' = {
  name: 'hostVmDeployment'
  params: {
    vmName: hostVmNameVar
    vmSize: hostVmSize
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: windowsAdminPassword
    location: location
    subnetId: networkDeployment.outputs.subnetId
    deployBastion: deployBastion
    dataDiskCount: hostDataDiskCount
    dataDiskSizeGB: hostDataDiskSizeGB
    enableAzureHybridBenefit: enableAzureHybridBenefit
    resourceTags: resourceTags
  }
}

module hostMonitoringDeployment 'mgmt/hostMonitoring.bicep' = {
  name: 'hostMonitoringDeployment'
  params: {
    vmName: hostVmNameVar
    workspaceName: mgmtArtifactsDeployment.outputs.workspaceName
    workspaceResourceId: mgmtArtifactsDeployment.outputs.workspaceId
    location: location
    resourceTags: resourceTags
  }
  dependsOn: [
    hostDeployment
  ]
}

module managementVmDeployment 'mgmt/mgmtVm.bicep' = if (deployManagementVm) {
  name: 'managementVmDeployment'
  params: {
    vmName: managementVmNameVar
    location: location
    vmSize: managementVmSize
    adminUsername: windowsAdminUsername
    adminPassword: windowsAdminPassword
    subnetId: networkDeployment.outputs.subnetId
    resourceTags: resourceTags
    enableAzureHybridBenefit: enableAzureHybridBenefit
  }
}

// --- Existing reference for least-privilege, resource-scoped role assignments ---
// Name is a deterministic var (computed above), so .id is calculable at start.
resource stagingStorageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' existing = {
  name: stagingStorageAccountName
}

// Host identity: read the staged ISOs and write build logs back.
resource hostStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(stagingStorageAccount.id, hostVmResourceId, roleStorageBlobDataContributor)
  scope: stagingStorageAccount
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleStorageBlobDataContributor
    principalType: 'ServicePrincipal'
  }
  // No explicit dependsOn needed: principalId reads hostDeployment's output, and
  // hostDeployment consumes stagingStorageDeployment's output — so this assignment
  // already orders after the storage account exists.
}

resource labKeyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: labKeyVaultName
}

// The vault is unreachable from outside the network, so the host reads its own
// credential on resume instead of the operator passing one in.
resource hostKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(labKeyVault.id, hostVmResourceId, roleKeyVaultSecretsUser)
  scope: labKeyVault
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleKeyVaultSecretsUser
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    labSecretsDeployment
  ]
}

// Host identity: Contributor on the RG so the in-VM Azure Local cluster deploy can
// create the cluster + supporting resources (Key Vault, witness storage, Arc).
resource hostContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, hostVmResourceId, roleContributor)
  scope: resourceGroup()
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleContributor
    principalType: 'ServicePrincipal'
  }
}

// Host identity: User Access Administrator on the RG. The create-cluster path performs
// role assignments for the deployment principals; Contributor alone CANNOT assign roles,
// so this is REQUIRED (and is the most commonly missed prerequisite). Scoped to the RG.
resource hostUserAccessAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, hostVmResourceId, roleUserAccessAdministrator)
  scope: resourceGroup()
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleUserAccessAdministrator
    principalType: 'ServicePrincipal'
  }
}

// Jumpbox identity: upload the operator-downloaded ISOs into the storage account.
resource jumpboxStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployManagementVm) {
  name: guid(stagingStorageAccount.id, managementVmResourceId, roleStorageBlobDataContributor)
  scope: stagingStorageAccount
  properties: {
    principalId: deployManagementVm ? managementVmDeployment!.outputs.managementVmPrincipalId : ''
    roleDefinitionId: roleStorageBlobDataContributor
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    stagingStorageDeployment
  ]
}

// The jumpbox is the operator's only route to the vault, since the private endpoint
// makes it unreachable from outside the network.
resource jumpboxKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployManagementVm) {
  name: guid(labKeyVault.id, managementVmResourceId, roleKeyVaultSecretsUser)
  scope: labKeyVault
  properties: {
    principalId: deployManagementVm ? managementVmDeployment!.outputs.managementVmPrincipalId : ''
    roleDefinitionId: roleKeyVaultSecretsUser
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    labSecretsDeployment
  ]
}

module hostBootstrapDeployment 'host/bootstrapExtension.bicep' = {
  name: 'hostBootstrapDeployment'
  params: {
    vmName: hostVmNameVar
    location: location
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: windowsAdminPassword
    stagingStorageAccountName: stagingStorageDeployment.outputs.storageAccountName
    isoContainerName: isoContainerName
    logsContainerName: logsContainerName
    workspaceName: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    artifactRef: artifactRef
    clusterName: clusterName
    clusterResourceSuffix: clusterResourceSuffix
    azureLocalInstanceLocation: azureLocalInstanceLocation
    hciResourceProviderObjectId: hciResourceProviderObjectId
    keyVaultName: labSecretsDeployment.outputs.keyVaultName
  }
  dependsOn: [
    hostStorageContributor
    hostContributor
    hostUserAccessAdmin
    hostKeyVaultSecretsUser
  ]
}

module jumpboxSetupDeployment 'mgmt/jumpboxSetup.bicep' = if (deployManagementVm) {
  name: 'jumpboxSetupDeployment'
  params: {
    vmName: managementVmNameVar
    location: location
    templateBaseUrl: templateBaseUrl
    artifactRef: artifactRef
    stagingStorageAccountName: stagingStorageDeployment.outputs.storageAccountName
    isoContainerName: isoContainerName
  }
  dependsOn: [
    jumpboxStorageContributor
  ]
}

output hostVmName string = hostDeployment.outputs.hostVmName
output stagingStorageAccountName string = stagingStorageDeployment.outputs.storageAccountName
output isoContainerName string = isoContainerName
output logsContainerName string = logsContainerName
output workspaceName string = mgmtArtifactsDeployment.outputs.workspaceName
output managementVmName string = deployManagementVm ? managementVmDeployment!.outputs.managementVmName : ''
output clusterResourceSuffix string = clusterResourceSuffix
output keyVaultName string = labSecretsDeployment.outputs.keyVaultName
