// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile · orchestrator.
//
// Stands up a clean-room, ZERO-Jumpstart Azure Local lab in a Bastion-only,
// NAT-gatewayed resource group:
//   • a hardened storage account holding the two operator-staged ISOs,
//   • a Windows Server 2025 jumpbox (the only place ISOs are downloaded),
//   • a large nested-virtualization cluster host that builds a nested domain
//     controller + a 3-node Azure Local cluster entirely from those ISOs,
//   • a Log Analytics workspace, Bastion, and NAT Gateway.
//
// Public-safe by construction: NO tenant GUIDs and NO secrets are committed.
// scripts/deploy-selfhosted.sh resolves the deployer object id + the Azure Local
// RP object id at deploy time and reads the Windows password from
// LOCALSELF_ADMIN_PASSWORD via readEnvironmentVariable().
//
// RBAC (assigned here so all principals resolve at the orchestration layer):
//   • deployer (human/SP)  -> Storage Blob Data Owner on the ISO storage
//   • host VM identity      -> Storage Blob Data Contributor on the ISO storage
//                              + Tag Contributor + Reader on the resource group
//                              + Contributor + User Access Administrator on the RG
//                                (the in-VM Azure Local cluster deploy performs
//                                 role assignments, so it needs UAA — Storage
//                                 data roles alone are NOT sufficient).
//   • jumpbox VM identity   -> Storage Blob Data Contributor on the ISO storage
// =============================================================================

@description('Username for the Windows accounts (host + jumpbox).')
param windowsAdminUsername string = 'arcdemo'

@description('Password for the Windows accounts. 12-123 chars; 3 of lower/upper/number/special.')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('Location to deploy all infrastructure resources.')
param location string = resourceGroup().location

@description('Resource-name prefix for the self-hosted resources.')
param namePrefix string = 'ApexLocal'

@description('Name for the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'ApexLocal-Workspace'

@description('Size of the nested-virtualization cluster-host VM.')
@allowed([
  'Standard_E32s_v5'
  'Standard_E48s_v5'
  'Standard_E64s_v5'
  'Standard_E32s_v6'
  'Standard_E48s_v6'
  'Standard_E64s_v6'
])
param hostVmSize string = 'Standard_E64s_v6'

@description('Number of Premium data disks pooled into the host V: drive.')
@minValue(4)
@maxValue(32)
param hostDataDiskCount int = 12

@description('Size (GB) of each host Premium data disk.')
param hostDataDiskSizeGB int = 256

@description('Apply Azure Hybrid Benefit (Windows_Server) across both VMs. Set false for license-included (PAYG).')
param enableAzureHybridBenefit bool = true

@description('Deploy Azure Bastion (true => no public IP on any VM; NAT Gateway egress).')
param deployBastion bool = true

@description('Deploy the Windows Server 2025 acquisition / management jumpbox.')
param deployManagementVm bool = true

@description('Size of the management jumpbox.')
param managementVmSize string = 'Standard_D4s_v5'

@description('Enable automatic logon so the in-VM build resumes headless after the Hyper-V reboot.')
param vmAutologon bool = true

// --- Azure Local cluster shape ---
@description('Number of nested Azure Local cluster nodes (3 = odd quorum, no witness).')
@allowed([
  2
  3
])
param clusterNodeCount int = 3

@description('Startup memory (MB) per nested Azure Local node.')
param nodeMemoryMB int = 98304

@description('Virtual processor count per nested Azure Local node.')
param nodeCpuCount int = 16

@description('Name of the Azure Local instance (cluster) resource created in Azure. 3-24 chars.')
@minLength(3)
@maxLength(24)
param clusterName string = 'apexlocal-cluster'

@description('Azure region the Azure Local INSTANCE is registered in (not every region supports the instance; keep separate from infra location).')
param azureLocalInstanceLocation string = 'westeurope'

// --- Artifact source (self-hosted in this repo) ---
@description('GitHub account that hosts this repository and its artifacts/ tree.')
param githubAccount string = 'jonathan-vella'

@description('GitHub repository name that hosts the vendored artifacts/ tree.')
param githubRepo string = 'apex-localops'

@description('GitHub branch or tag. Use a release tag for reproducible deploys; "main" tracks latest.')
param githubBranch string = 'main'

@description('Name of the ISO blob container.')
param isoContainerName string = 'iso-images'

@description('Name of the build-logs blob container.')
param logsContainerName string = 'logs'

// --- Identity inputs (resolved at deploy time; never committed) ---
@description('Object id of the principal RUNNING the deployment. Granted Storage Blob Data Owner so it (and the operator on the jumpbox) can upload the ISOs. scripts/deploy-selfhosted.sh resolves the signed-in user automatically. Leave empty to skip.')
param deployerPrincipalId string = ''

@description('Principal type for deployerPrincipalId. "User" for an individual, "ServicePrincipal" for CI.')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param deployerPrincipalType string = 'User'

@description('Object id of the Azure Local Resource Provider service principal (app 1412d89f-b8a8-4111-b4fd-e82905cbd85d) in this tenant. Required by the in-VM cluster deploy; resolved at deploy time by scripts/deploy-selfhosted.sh.')
param hciResourceProviderObjectId string = ''

@description('Add CostControl/SecurityControl tags (Microsoft-internal lab tenants only).')
param governResourceTags bool = false

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

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/${githubRepo}/${githubBranch}/'

// Deterministic resource names (calculable at the start of the deployment) so that
// resource-scoped role-assignment names/scopes don't depend on runtime module outputs.
var stagingStorageAccountName = 'apexloc${uniqueString(resourceGroup().id)}'
var hostVmNameVar = '${namePrefix}-Host'
var managementVmNameVar = '${namePrefix}-Mgmt'
var hostVmResourceId = resourceId('Microsoft.Compute/virtualMachines', hostVmNameVar)
var managementVmResourceId = resourceId('Microsoft.Compute/virtualMachines', managementVmNameVar)

// Built-in role definition IDs.
var roleStorageBlobDataOwner = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
)
var roleStorageBlobDataContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)
var roleTagContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
)
var roleReader = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
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

module stagingStorageDeployment 'mgmt/stagingStorage.bicep' = {
  name: 'stagingStorageDeployment'
  params: {
    location: location
    storageAccountName: stagingStorageAccountName
    isoContainerName: isoContainerName
    logsContainerName: logsContainerName
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
    stagingStorageAccountName: stagingStorageDeployment.outputs.storageAccountName
    isoContainerName: isoContainerName
    logsContainerName: logsContainerName
    workspaceName: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    vmAutologon: vmAutologon
    clusterNodeCount: clusterNodeCount
    nodeMemoryMB: nodeMemoryMB
    nodeCpuCount: nodeCpuCount
    clusterName: clusterName
    azureLocalInstanceLocation: azureLocalInstanceLocation
    hciResourceProviderObjectId: hciResourceProviderObjectId
  }
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
    templateBaseUrl: templateBaseUrl
    stagingStorageAccountName: stagingStorageAccountName
    isoContainerName: isoContainerName
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

// Host identity: write ApexProgress/ApexStatus tags on the resource group.
resource hostTagContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, hostVmResourceId, roleTagContributor)
  scope: resourceGroup()
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleTagContributor
    principalType: 'ServicePrincipal'
  }
}

// Host identity: read resource-group metadata.
resource hostReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, hostVmResourceId, roleReader)
  scope: resourceGroup()
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleReader
    principalType: 'ServicePrincipal'
  }
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

// Deployer (human / SP / group): Storage Blob Data OWNER on the staging account so it can
// upload the ISOs (from the jumpbox or Cloud Shell). Control-plane roles (Owner/Contributor)
// do NOT grant blob data access, so this is required for the upload path to work.
resource deployerStorageOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(stagingStorageAccount.id, deployerPrincipalId, roleStorageBlobDataOwner)
  scope: stagingStorageAccount
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: roleStorageBlobDataOwner
    principalType: deployerPrincipalType
  }
  dependsOn: [
    stagingStorageDeployment
  ]
}

output hostVmName string = hostDeployment.outputs.hostVmName
output stagingStorageAccountName string = stagingStorageDeployment.outputs.storageAccountName
output isoContainerName string = isoContainerName
output logsContainerName string = logsContainerName
output workspaceName string = mgmtArtifactsDeployment.outputs.workspaceName
output managementVmName string = deployManagementVm ? managementVmDeployment!.outputs.managementVmName : ''
