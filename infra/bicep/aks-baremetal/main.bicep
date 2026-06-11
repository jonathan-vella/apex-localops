// =============================================================================
// apex-localops — AKS on bare metal (preview) on an SFF Arc-enabled machine.
//
// This is the DOWNSTREAM continuation of the Azure Local SFF profile
// (infra/bicep/azlocal-sff). It deploys a single-node Kubernetes cluster directly
// onto the Arc-enabled SFF edge machine that the SFF flow produces AFTER the machine
// is provisioned from the Azure portal (see docs/sff-runbook.md). It therefore runs
// as a SEPARATE, post-provisioning deployment — the edge machine must already be in
// the "Provisioned" state.
//
// Mirrors the upstream Azure/aksArc Bicep template (deploymentTemplates/
// aks-baremetal-bicep/cluster-create.bicep) for parity with the portal create flow.
// Resource creation order:
//   1. DevicePool          — binds the EdgeMachine to a CMP instance; the HCI RP
//                            AUTO-CREATES the CustomLocation during provisioning.
//   2. RBAC (DevicePool MSI → Device Pool Manager on the DevicePool).
//   3. RBAC (DevicePool MSI → Edge Machine Contributor on the EdgeMachine).
//   4. LogicalNetwork      — placeholder required by the provisioned-cluster webhook
//                            (infraNetworkProfile validation); not used for networking.
//   5. connectedCluster    — Arc projection (kind 'ProvisionedCluster') carrying the
//                            identity + the Entra admin group (Azure RBAC for K8s).
//   6. provisionedClusterInstance ('default') — the actual single-node cluster.
//   7. (optional) Azure Policy extension.
//   8. (optional) Container Monitoring extension.
//
// PREVIEW: AKS on bare metal is in preview — East US only, single control-plane
// node, Cilium. Kubernetes version is a free-form, date-suffixed string (e.g.
// '1.34.3-20260204'). The API versions below are the preview-volatile seam.
//
// Public-safe by construction: NO tenant GUIDs and NO secrets are committed.
// scripts/deploy-aks-baremetal.sh resolves the tenant-specific values at deploy
// time from environment variables (see main.bicepparam).
// =============================================================================

// --- Basics (portal: Basics tab) ---

@description('Name of the AKS on bare metal cluster. 1-27 chars; start/end alphanumeric; letters, numbers, hyphens, underscores.')
@minLength(1)
@maxLength(27)
param clusterName string = 'localsff-aks'

@description('Azure region. AKS on bare metal public preview is East US only. Must match the edge machine region.')
@allowed([
  'eastus'
])
param location string = 'eastus'

@description('Kubernetes version. Free-form, date-suffixed string per the preview (e.g. 1.34.3-20260204). See the create-cluster doc for the current supported values.')
param kubernetesVersion string

@description('Control plane (Kubernetes API server) IP. Must be in the same subnet as the edge machine and NOT the machine IP. Reserve it in DHCP so it never changes.')
param controlPlaneIp string

// --- Access (portal: Access tab) ---

@description('Enable Azure RBAC for Kubernetes authorization on the connected cluster.')
param enableAzureRbac bool = true

@description('Microsoft Entra ID security group object IDs granted cluster admin (Azure RBAC for Kubernetes).')
param adminGroupObjectIds array

@description('SSH public key (OpenSSH) authorized for the cluster node VMs. Required by the AksArc-Operator webhook. Not a secret, but tenant-specific — pass at deploy time.')
param sshPublicKey string

// --- Integrations (portal: Integrations tab) ---

@description('Auto-enable the Azure Policy extension on the cluster.')
param enableAzurePolicy bool = true

@description('Auto-enable the Container Monitoring (Azure Monitor) extension. Requires logAnalyticsWorkspaceId; skipped when that is empty.')
param enableContainerMonitoring bool = true

@description('Log Analytics workspace resource ID for Container Monitoring. Required when enableContainerMonitoring is true; leave empty to skip monitoring.')
param logAnalyticsWorkspaceId string = ''

// --- Infrastructure ---

@description('Name of the existing EdgeMachine resource (must be in the Provisioned state) in this resource group.')
param edgeMachineName string

@description('Name for the DevicePool resource. Defaults to the edge machine name.')
param devicePoolName string = edgeMachineName

@description('Name for the CustomLocation the HCI RP creates during DevicePool provisioning. Defaults to the edge machine name.')
param customLocationName string = edgeMachineName

@description('Tags applied to all created resources.')
param tags object = {
  Project: 'apex_localsff'
  Workload: 'aks-baremetal'
}

// --- Preview-volatile API versions (centralized for easy bump) ---
// --- Preview-volatile API versions (centralized for easy bump). Verified against the
// provider's supported set on 2026-06-11 — the upstream template's older versions are no
// longer registered in this tenant. Re-check with: az provider show --namespace <ns>
// --query "resourceTypes[?resourceType=='<type>'].apiVersions". ---
var devicePoolApiVersion = '2026-05-01-preview'
var edgeMachineApiVersion = '2026-05-01-preview'
var logicalNetworkApiVersion = '2026-04-01-preview'
var connectedClusterApiVersion = '2024-01-01'
var provisionedClusterApiVersion = '2024-01-01'
var extensionApiVersion = '2023-05-01'

// --- Constants (public preview) ---
var controlPlaneCount = 1
var podCidr = '10.244.0.0/16'
// The LogicalNetwork is required by the provisioned-cluster webhook
// (infraNetworkProfile validation) but is never used for actual networking. These
// are valid placeholder values that pass the API's IP validation.
var lnetName = '${clusterName}-lnet'
var lnetAddressPrefix = '10.0.0.0/24'
var lnetGateway = '10.0.0.1'
var lnetIpPoolStart = '10.0.0.2'
var lnetIpPoolEnd = '10.0.0.10'
var lnetVmSwitchName = 'PlaceholderSwitch'

// --- Derived values ---
var edgeMachineResourceId = resourceId('Microsoft.AzureStackHCI/edgeMachines', edgeMachineName)
var customLocationResourceId = resourceId('Microsoft.ExtendedLocation/customLocations', customLocationName)
var mergedTags = union(tags, {
  'aks-arc-cluster': clusterName
  purpose: 'aks-arc-bmlinux'
})

// Well-known role definition IDs.
var devicePoolManagerRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'adc3c795-c41e-4a89-a478-0b321783324c'
)
var edgeMachineContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '1a6f9009-515c-4455-b170-143e4c9ce229'
)

// 1. DevicePool — binds the EdgeMachine to a CMP instance. The HCI RP auto-creates
// the CustomLocation during DevicePool provisioning (we do NOT create the CL).
resource devicePool 'Microsoft.AzureStackHCI/devicePools@2026-05-01-preview' = {
  name: devicePoolName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    devices: [
      {
        deviceResourceId: edgeMachineResourceId
      }
    ]
    customLocationName: customLocationName
  }
  tags: mergedTags
}

// 2. RBAC — DevicePool MSI → Device Pool Manager on the DevicePool. The role
// assignment name must be deterministic at deploy-start, so the seed uses the
// DevicePool name (not the runtime principalId).
resource dpManagerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(devicePool.id, 'dpManager', devicePoolManagerRoleId)
  scope: devicePool
  properties: {
    roleDefinitionId: devicePoolManagerRoleId
    principalId: devicePool.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'DevicePool MSI needs Device Pool Manager for CAPE operations.'
  }
}

// 3. RBAC — DevicePool MSI → Edge Machine Contributor on the EdgeMachine (same RG).
resource edgeMachine 'Microsoft.AzureStackHCI/edgeMachines@2026-05-01-preview' existing = {
  name: edgeMachineName
}

resource emContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(edgeMachineResourceId, 'emContributor', edgeMachineContributorRoleId)
  scope: edgeMachine
  properties: {
    roleDefinitionId: edgeMachineContributorRoleId
    principalId: devicePool.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'DevicePool MSI needs Edge Machine Contributor for CAPE lifecycle operations.'
  }
}

// 4. LogicalNetwork (placeholder) — required by the provisioned-cluster webhook but
// not used for actual networking. Created with valid dummy values to pass validation.
resource logicalNetwork 'Microsoft.AzureStackHCI/logicalNetworks@2026-04-01-preview' = {
  name: lnetName
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationResourceId
  }
  properties: {
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: lnetAddressPrefix
          ipAllocationMethod: 'Static'
          ipPools: [
            {
              start: lnetIpPoolStart
              end: lnetIpPoolEnd
            }
          ]
          routeTable: {
            properties: {
              routes: [
                {
                  name: 'default'
                  properties: {
                    addressPrefix: '0.0.0.0/0'
                    nextHopIpAddress: lnetGateway
                  }
                }
              ]
            }
          }
        }
      }
    ]
    vmSwitchName: lnetVmSwitchName
  }
  tags: mergedTags
  dependsOn: [
    // CustomLocation must exist (created by the HCI RP during DevicePool provisioning).
    devicePool
  ]
}

// 5. Connected Cluster — the Arc projection. kind 'ProvisionedCluster' + an empty
// agentPublicKeyCertificate is the documented convention (the certificate is managed
// by the provisioned cluster instance).
resource connectedCluster 'Microsoft.Kubernetes/connectedClusters@2024-01-01' = {
  name: clusterName
  location: location
  kind: 'ProvisionedCluster'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    agentPublicKeyCertificate: ''
    aadProfile: {
      enableAzureRBAC: enableAzureRbac
      adminGroupObjectIDs: adminGroupObjectIds
    }
  }
  tags: mergedTags
  dependsOn: [
    logicalNetwork
  ]
}

// 6. Provisioned Cluster Instance — the actual cluster. An extension on the connected
// cluster, pinned to the SFF edge machine via the custom location. name MUST be 'default'.
resource provisionedClusterInstance 'Microsoft.HybridContainerService/provisionedClusterInstances@2024-01-01' = {
  name: 'default'
  scope: connectedCluster
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationResourceId
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    controlPlane: {
      count: controlPlaneCount
      controlPlaneEndpoint: {
        hostIP: controlPlaneIp
      }
    }
    networkProfile: {
      podCidr: podCidr
      // Cilium is the only supported CNI for AKS on bare metal SFF. Set it explicitly:
      // the GA 2024-01-01 API defaults networkPolicy to 'calico' when omitted, which is
      // not supported on this platform.
      networkPolicy: 'cilium'
      loadBalancerProfile: {
        // LoadBalancer type is not supported in preview; use NodePort for workloads.
        count: 0
      }
    }
    cloudProviderProfile: {
      infraNetworkProfile: {
        vnetSubnetIds: [
          logicalNetwork.id
        ]
      }
    }
    // Single control-plane node only in preview; agent pools are empty.
    agentPoolProfiles: []
    linuxProfile: {
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
  }
}

// 7. (Optional) Azure Policy extension.
resource azurePolicyExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = if (enableAzurePolicy) {
  name: 'azure-policy'
  scope: connectedCluster
  properties: {
    extensionType: 'microsoft.policyinsights'
    autoUpgradeMinorVersion: true
  }
  dependsOn: [
    provisionedClusterInstance
  ]
}

// 8. (Optional) Container Monitoring extension. Deployed only when a workspace is given.
resource containerMonitoringExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = if (enableContainerMonitoring && !empty(logAnalyticsWorkspaceId)) {
  name: 'azuremonitor-containers'
  scope: connectedCluster
  properties: {
    extensionType: 'microsoft.azuremonitor.containers'
    autoUpgradeMinorVersion: true
    configurationSettings: {
      logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
    }
  }
  dependsOn: [
    provisionedClusterInstance
  ]
}

output connectedClusterName string = connectedCluster.name
output connectedClusterId string = connectedCluster.id
output provisionedClusterInstanceId string = provisionedClusterInstance.id
output devicePoolId string = devicePool.id
output devicePoolPrincipalId string = devicePool.identity.principalId
output customLocationId string = customLocationResourceId
output connectCommand string = 'az connectedk8s proxy --name ${connectedCluster.name} --resource-group ${resourceGroup().name}'
output apiVersions object = {
  devicePools: devicePoolApiVersion
  edgeMachines: edgeMachineApiVersion
  logicalNetworks: logicalNetworkApiVersion
  connectedClusters: connectedClusterApiVersion
  provisionedClusterInstances: provisionedClusterApiVersion
  extensions: extensionApiVersion
}
