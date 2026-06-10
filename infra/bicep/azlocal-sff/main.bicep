// =============================================================================
// apex-localops — Azure Local Small Form Factor (SFF) profile · orchestrator.
//
// Stands up a single nested-virtualization Hyper-V host (plus an optional Win11
// acquisition jumpbox) in a Bastion-only, NAT-gatewayed resource group. The host
// builds an Azure Local SFF *test* VM (ROE Maintenance OS) inside itself and
// drives it to the "ROE setup completed successfully" success gate.
//
// Public-safe by construction: NO tenant GUIDs and NO secrets are committed.
// scripts/deploy-sff.sh resolves tenantId at deploy time and reads the Windows
// password from LOCALSFF_ADMIN_PASSWORD via readEnvironmentVariable().
// =============================================================================

@description('Username for the Windows accounts (host + jumpbox).')
param windowsAdminUsername string = 'arcdemo'

@description('Password for the Windows accounts. 12-123 chars; 3 of lower/upper/number/special.')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('Location to deploy all resources.')
param location string = resourceGroup().location

@description('Resource-name prefix for the SFF resources.')
param namePrefix string = 'LocalSFF'

@description('Name for the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'LocalSFF-Workspace'

@description('Size of the nested-virtualization Hyper-V host VM.')
@allowed([
  'Standard_D8s_v5'
  'Standard_D16s_v5'
  'Standard_E8s_v5'
  'Standard_E16s_v5'
  'Standard_D8s_v6'
  'Standard_D16s_v6'
  'Standard_E8s_v6'
  'Standard_E16s_v6'
])
param hostVmSize string = 'Standard_D8s_v5'

@description('Size of the single Premium data disk (drive V:) on the host.')
@minValue(256)
@maxValue(2048)
param hostDataDiskSizeGB int = 512

@description('Deploy Azure Bastion (true => no public IP on any VM; NAT Gateway egress).')
param deployBastion bool = true

@description('Deploy the optional Windows 11 acquisition / management jumpbox.')
param deployManagementVm bool = true

@description('Size of the Windows 11 management jumpbox.')
param managementVmSize string = 'Standard_D4s_v5'

@description('Enable automatic logon so the in-VM build resumes headless after the Hyper-V reboot.')
param vmAutologon bool = true

@description('Public DNS handed out by the internal Hyper-V DHCP scope.')
param natDNS string = '8.8.8.8'

@description('Blob container that holds the staged ROE ISO + Configurator App MSI.')
param stagingArtifactsContainer string = 'sff-artifacts'

// --- Nested SFF test VM geometry ---
@description('Name of the nested SFF test VM.')
param nestedVmName string = 'linuxsff-vm'

@description('Startup memory (MB) for the nested SFF test VM.')
param nestedVmMemoryMB int = 16000

@description('Virtual processor count for the nested SFF test VM. Must be >= 4.')
@minValue(4)
param nestedVmCpuCount int = 4

@description('OS disk size (GB) for the nested SFF test VM.')
param nestedVmDiskGB int = 256

@description('Name of the internal Hyper-V switch created on the host.')
param hvSwitchName string = 'HV-Internal-NAT'

@description('IPv4 CIDR for the internal Hyper-V NAT subnet.')
param hvSubnetPrefix string = '192.168.200.0/24'

@description('Host-side gateway IP on the internal Hyper-V switch.')
param hvGateway string = '192.168.200.1'

// --- Artifact source (self-hosted in this repo) ---
@description('GitHub account that hosts this repository and its artifacts/ tree.')
param githubAccount string = 'jonathan-vella'

@description('GitHub repository name that hosts the vendored artifacts/ tree.')
param githubRepo string = 'apex-localops'

@description('GitHub branch or tag. Use a release tag for reproducible deploys; "main" tracks latest.')
param githubBranch string = 'main'

@description('Optional object id of the human operator (or a group) to grant Storage Blob Data Contributor on the staging account, so they can stage the ROE ISO + Configurator App via the Azure portal blob browser or `--auth-mode login`. Owner/Contributor are control-plane only and do NOT grant blob data access. scripts/deploy-sff.sh resolves the signed-in user automatically. Leave empty to skip.')
param operatorPrincipalId string = ''

@description('Principal type for operatorPrincipalId. "User" for an individual, "Group" for an Entra group.')
@allowed([
  'User'
  'Group'
])
param operatorPrincipalType string = 'User'

@description('Add CostControl/SecurityControl tags (Microsoft-internal lab tenants only).')
param governResourceTags bool = false

@description('Tags applied to all resources.')
param tags object = {
  Project: 'apex_localsff'
}

var resourceTags = governResourceTags
  ? union(tags, {
      CostControl: 'Ignore'
      SecurityControl: 'Ignore'
    })
  : tags

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/${githubRepo}/${githubBranch}/'
var customerUsageAttributionDeploymentName = 'pid-feada075-1961-4b99-829f-fa3828068933-sff'

// Deterministic resource names (calculable at the start of the deployment) so that
// resource-scoped role-assignment names/scopes don't depend on runtime module outputs.
var stagingStorageAccountName = 'localsff${uniqueString(resourceGroup().id)}'
var keyVaultName = 'sffkv${uniqueString(resourceGroup().id)}'
var hostVmNameVar = '${namePrefix}-Host'
var managementVmNameVar = '${namePrefix}-Mgmt'
var hostVmResourceId = resourceId('Microsoft.Compute/virtualMachines', hostVmNameVar)
var managementVmResourceId = resourceId('Microsoft.Compute/virtualMachines', managementVmNameVar)

// Built-in role definition IDs.
var roleStorageBlobDataReader = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
)
var roleStorageBlobDataContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)
var roleKeyVaultSecretsOfficer = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
)
var roleTagContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
)
var roleReader = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
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
    stagingArtifactsContainer: stagingArtifactsContainer
    resourceTags: resourceTags
  }
}

module keyVaultDeployment 'mgmt/keyVault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    location: location
    keyVaultName: keyVaultName
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
    dataDiskSizeGB: hostDataDiskSizeGB
    resourceTags: resourceTags
    stagingStorageAccountName: stagingStorageDeployment.outputs.storageAccountName
    stagingArtifactsContainer: stagingArtifactsContainer
    keyVaultName: keyVaultDeployment.outputs.keyVaultName
    workspaceName: logAnalyticsWorkspaceName
    templateBaseUrl: templateBaseUrl
    vmAutologon: vmAutologon
    natDNS: natDNS
    nestedVmName: nestedVmName
    nestedVmMemoryMB: nestedVmMemoryMB
    nestedVmCpuCount: nestedVmCpuCount
    nestedVmDiskGB: nestedVmDiskGB
    hvSwitchName: hvSwitchName
    hvSubnetPrefix: hvSubnetPrefix
    hvGateway: hvGateway
  }
}

module managementVmDeployment 'mgmt/managementVm.bicep' = if (deployManagementVm) {
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
    stagingArtifactsContainer: stagingArtifactsContainer
    resourceTags: resourceTags
  }
}

// --- Existing references for least-privilege, resource-scoped role assignments ---
// Names are deterministic vars (computed above), so .id is calculable at start.
resource stagingStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: stagingStorageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Host identity: read staged artifacts from the staging storage account.
resource hostStorageReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(stagingStorageAccount.id, hostVmResourceId, roleStorageBlobDataReader)
  scope: stagingStorageAccount
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleStorageBlobDataReader
    principalType: 'ServicePrincipal'
  }
}

// Host identity: write the ownership voucher into the Key Vault.
resource hostKeyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, hostVmResourceId, roleKeyVaultSecretsOfficer)
  scope: keyVault
  properties: {
    principalId: hostDeployment.outputs.hostPrincipalId
    roleDefinitionId: roleKeyVaultSecretsOfficer
    principalType: 'ServicePrincipal'
  }
}

// Host identity: write SffProgress/SffStatus tags on the resource group.
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

// Jumpbox identity: upload the portal-downloaded artifacts into the staging SA.
resource jumpboxStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployManagementVm) {
  name: guid(stagingStorageAccount.id, managementVmResourceId, roleStorageBlobDataContributor)
  scope: stagingStorageAccount
  properties: {
    principalId: deployManagementVm ? managementVmDeployment!.outputs.managementVmPrincipalId : ''
    roleDefinitionId: roleStorageBlobDataContributor
    principalType: 'ServicePrincipal'
  }
}

// Operator (human / group): Storage Blob Data Contributor on the staging account so they can
// stage the ROE ISO + Configurator App from the Azure portal blob browser or `--auth-mode
// login`. Control-plane roles (Owner/Contributor) do NOT grant blob data access; this closes
// the "not authorized to perform this operation using this permission" gap.
resource operatorStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(operatorPrincipalId)) {
  name: guid(stagingStorageAccount.id, operatorPrincipalId, roleStorageBlobDataContributor)
  scope: stagingStorageAccount
  properties: {
    principalId: operatorPrincipalId
    roleDefinitionId: roleStorageBlobDataContributor
    principalType: operatorPrincipalType
  }
}

module customerUsageAttribution 'mgmt/customerUsageAttribution.bicep' = {
  name: customerUsageAttributionDeploymentName
  params: {}
}

output hostVmName string = hostDeployment.outputs.hostVmName
output stagingStorageAccountName string = stagingStorageDeployment.outputs.storageAccountName
output stagingArtifactsContainer string = stagingArtifactsContainer
output keyVaultName string = keyVaultDeployment.outputs.keyVaultName
output managementVmName string = deployManagementVm ? managementVmDeployment!.outputs.managementVmName : ''
