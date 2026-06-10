@description('Azure AD tenant id for your service principal')
param tenantId string

@description('Azure AD object id for your Microsoft.AzureStackHCI resource provider')
param spnProviderId string

@description('Username for Windows account')
param windowsAdminUsername string

@description('Password for Windows account. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('Name for your log analytics workspace')
param logAnalyticsWorkspaceName string = 'LocalBox-Workspace'

@description('Public DNS to use for the domain')
param natDNS string = '8.8.8.8'

@description('Target GitHub account that hosts this repository and its artifacts/ tree')
param githubAccount string = 'jonathan-vella'

@description('Target GitHub repository name that hosts the vendored artifacts/ tree')
param githubRepo string = 'apex-localops'

@description('Target GitHub branch or tag. Use a release tag (e.g. v1.0.0) to pin a frozen, reproducible artifact set; "main" tracks the latest.')
param githubBranch string = 'main'

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = false

@description('Location to deploy resources (except Azure Local cluster resource)')
param location string = resourceGroup().location

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string = '3389'

@description('Choice to enable automatic deployment of Azure Local cluster resource after the client VM deployment is complete. Default is false.')
param autoDeployClusterResource bool = true

@description('Choice to enable automatic upgrade of Azure Local cluster resource after the client VM deployment is complete. Only applicable when autoDeployClusterResource is true. Default is false.')
param autoUpgradeClusterResource bool = false

@description('Enable automatic logon into LocalBox Virtual Machine')
param vmAutologon bool = true

@description('Name of the NAT Gateway')
param natGatewayName string = 'LocalBox-NatGateway'

@description('The size of the Virtual Machine')
@allowed([
  'Standard_E32s_v5'
  'Standard_E32s_v6'
  'Standard_E64s_v6'
])
param vmSize string = 'Standard_E32s_v6'

@description('Number of nested Azure Local cluster nodes. 3 = odd quorum, NO witness needed (default; pair with Standard_E64s_v6). 2 = requires a cloud witness (pair with Standard_E32s_v6, and only where storage shared-key access is allowed).')
@allowed([
  2
  3
])
param clusterNodeCount int = 3

@description('Number of 256 GB P30 data disks on the host VM (the V: storage pool). 12 suits the 3-node cluster; 8 is enough for 2 nodes.')
@minValue(8)
@maxValue(32)
param dataDiskCount int = 12

@description('Option to enable spot pricing for the LocalBox Client VM')
param enableAzureSpotPricing bool = false

@description('Setting this parameter to `true` will add the `CostControl` and `SecurityControl` tags to the provisioned resources. These tags are applicable to ONLY Microsoft-internal Azure lab tenants and designed for managing automated governance processes related to cost optimization and security controls')
param governResourceTags bool = true

@description('Tags to be added to all resources')

param tags object = {
  Project: 'jumpstart_LocalBox'
}

@description('Region to register Azure Local instance in. This is the region where the Azure Local instance resources will be created. The region must be one of the supported Azure Local regions.')
@allowed([
  'australiaeast'
  'southcentralus'
  'eastus'
  'westeurope'
  'southeastasia'
  'canadacentral'
  'japaneast'
  'centralindia'
])
param azureLocalInstanceLocation string = 'australiaeast'

// JS-LOCAL CUSTOMIZATION: optional Windows 11 management/jumpbox VM (reached via Bastion).
@description('JS-LOCAL CUSTOMIZATION: deploy a Windows 11 management/jumpbox VM on the LocalBox workload subnet, reachable over Azure Bastion.')
param deployManagementVm bool = true

@description('JS-LOCAL CUSTOMIZATION: size of the Windows 11 management VM.')
param managementVmSize string = 'Standard_D4s_v5'

// if governResourceTags is true, add the following tags
var resourceTags = governResourceTags ? union(tags, {
    CostControl: 'Ignore'
    SecurityControl: 'Ignore'
}) : tags

// apex-localops: artifacts are vendored at the repository root (artifacts/...), served
// over raw.githubusercontent.com from this repo itself - no microsoft/azure_arc runtime
// dependency. Pin githubBranch to a release tag for reproducible deploys.
var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/${githubRepo}/${githubBranch}/'
var customerUsageAttributionDeploymentName = 'feada075-1961-4b99-829f-fa3828068933'

module mgmtArtifactsAndPolicyDeployment 'mgmt/mgmtArtifacts.bicep' = {
  name: 'mgmtArtifactsAndPolicyDeployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    resourceTags: resourceTags
  }
}

module networkDeployment 'network/network.bicep' = {
  name: 'networkDeployment'
  params: {
    deployBastion: deployBastion
    location: location
    resourceTags: resourceTags
    natGatewayName: natGatewayName
  }
}

module storageAccountDeployment 'mgmt/storageAccount.bicep' = {
  name: 'stagingStorageAccountDeployment'
  params: {
    // JS-LOCAL FIX (root cause of the failed cluster build): this staging storage
    // account ALSO serves as the Azure Local *cluster witness*. Generate-ARM-Template.ps1
    // maps it to `ClusterWitnessStorageAccountName`, and azlocal.json creates the witness
    // with `location: [parameters('location')]` = azureLocalInstanceLocation. If the
    // account already exists in a different region, the in-VM cloud deployment aborts with
    // `InvalidResourceLocation`. A previous swedencentral override caused exactly that, so
    // the witness/staging account MUST live in the Azure Local instance region.
    location: azureLocalInstanceLocation
    resourceTags: resourceTags
  }
}

module hostDeployment 'host/host.bicep' = {
  name: 'hostVmDeployment'
  params: {
    vmSize: vmSize
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: windowsAdminPassword
    tenantId: tenantId
    spnProviderId: spnProviderId
    workspaceName: logAnalyticsWorkspaceName
    stagingStorageAccountName: storageAccountDeployment.outputs.storageAccountName
    templateBaseUrl: templateBaseUrl
    subnetId: networkDeployment.outputs.subnetId
    deployBastion: deployBastion
    natDNS: natDNS
    location: location
    rdpPort: rdpPort
    autoDeployClusterResource: autoDeployClusterResource
    autoUpgradeClusterResource: autoUpgradeClusterResource
    vmAutologon: vmAutologon
    resourceTags: resourceTags
    enableAzureSpotPricing: enableAzureSpotPricing
    azureLocalInstanceLocation: azureLocalInstanceLocation
    clusterNodeCount: clusterNodeCount
    dataDiskCount: dataDiskCount
  }
}

// JS-LOCAL CUSTOMIZATION: Windows 11 management/jumpbox VM on the workload subnet.
module managementVmDeployment 'mgmt/managementVm.bicep' = if (deployManagementVm) {
  name: 'managementVmDeployment'
  params: {
    location: location
    vmSize: managementVmSize
    adminUsername: windowsAdminUsername
    adminPassword: windowsAdminPassword
    subnetId: networkDeployment.outputs.subnetId
    resourceTags: resourceTags
  }
}

module customerUsageAttribution 'mgmt/customerUsageAttribution.bicep' = {
  name: 'pid-${customerUsageAttributionDeploymentName}'
  params: {
  }
}
