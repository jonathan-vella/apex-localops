// =============================================================================
// apex-localops — AKS on bare metal (preview) on an SFF Arc-enabled machine.
//
// This is the DOWNSTREAM continuation of the Azure Local SFF profile
// (infra/bicep/azlocal-sff). It deploys a single-node Kubernetes cluster directly
// onto the Arc-enabled SFF machine that the SFF flow produces AFTER the machine is
// provisioned from the Azure portal (see docs/sff-runbook.md). It therefore runs
// as a SEPARATE, post-provisioning deployment — the custom location and control-
// plane IP it needs only exist once the edge machine is "Provisioned".
//
// Models the standard AKS-Arc "provisioned cluster" pair:
//   * Microsoft.Kubernetes/connectedClusters (kind 'ProvisionedCluster') — the Arc
//     projection that carries identity + the Entra admin group (Azure RBAC for K8s).
//   * Microsoft.HybridContainerService/provisionedClusterInstances (name 'default')
//     — the actual cluster, an extension on the connected cluster, pinned to the SFF
//     edge machine via extendedLocation = its custom location.
//
// PREVIEW: AKS on bare metal is in preview (East US only, K8s 1.34.2/1.34.3,
// single-node, Cilium). The API versions below are the preview-volatile seam.
//
// Public-safe by construction: NO tenant GUIDs and NO secrets are committed.
// scripts/deploy-aks-baremetal.sh resolves the tenant-specific values at deploy
// time from environment variables (see main.bicepparam).
// =============================================================================

@description('Name of the AKS on bare metal cluster (no spaces).')
param clusterName string = 'localsff-aks'

@description('Azure region. AKS on bare metal public preview is East US only.')
@allowed([
  'eastus'
])
param location string = 'eastus'

@description('ARM resource ID of the custom location of the provisioned SFF edge machine. Obtain it after the machine is Provisioned (az customlocation list / the machine resource).')
param customLocationId string

@description('Kubernetes version. Preview supports 1.34.2 and 1.34.3.')
@allowed([
  '1.34.2'
  '1.34.3'
])
param kubernetesVersion string = '1.34.3'

@description('Control plane (Kubernetes API server) IP. Must be in the same subnet as the edge machine and NOT the machine IP. Reserve it in DHCP so it never changes.')
param controlPlaneIP string

@description('SSH public key (PEM/OpenSSH) authorized for the cluster node VMs. Not a secret, but tenant-specific — pass at deploy time.')
param sshPublicKey string

@description('Microsoft Entra ID security group object ID granted cluster admin (Azure RBAC for Kubernetes).')
param adminGroupObjectId string

@description('Enable Azure RBAC for Kubernetes authorization on the connected cluster.')
param enableAzureRBAC bool = true

@description('Pod CIDR for the cluster network (Cilium).')
param podCidr string = '10.244.0.0/16'

@description('Number of agent pool nodes. Preview is single-node (1).')
@minValue(1)
param agentNodeCount int = 1

@description('Name of the default agent pool.')
param agentPoolName string = 'nodepool1'

@description('Optional ARM resource ID of a logical network for the cluster (not needed for single-node clusters). Leave empty to omit.')
param logicalNetworkId string = ''

@description('Tags applied to the connected cluster resource.')
param tags object = {
  Project: 'apex_localsff'
  Workload: 'aks-baremetal'
}

// --- Preview-volatile API versions (centralized for easy bump) ---
var connectedClusterApiVersion = '2024-07-15-preview'
var provisionedClusterApiVersion = '2026-04-01-preview'

// The Arc projection of the cluster. kind 'ProvisionedCluster' + an empty
// agentPublicKeyCertificate is the documented convention for AKS-Arc provisioned
// clusters (the certificate is managed by the provisioned cluster instance).
resource connectedCluster 'Microsoft.Kubernetes/connectedClusters@2024-07-15-preview' = {
  name: clusterName
  location: location
  kind: 'ProvisionedCluster'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    agentPublicKeyCertificate: ''
    aadProfile: {
      adminGroupObjectIDs: [
        adminGroupObjectId
      ]
      enableAzureRBAC: enableAzureRBAC
    }
  }
  tags: tags
}

// The actual cluster: an extension resource on the connected cluster, pinned to the
// SFF edge machine via the custom location. name MUST be 'default'.
resource provisionedClusterInstance 'Microsoft.HybridContainerService/provisionedClusterInstances@2026-04-01-preview' = {
  name: 'default'
  scope: connectedCluster
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    controlPlane: {
      count: 1
      controlPlaneEndpoint: {
        hostIP: controlPlaneIP
      }
    }
    agentPoolProfiles: [
      {
        name: agentPoolName
        count: agentNodeCount
        osType: 'Linux'
        osSKU: 'CBLMariner'
      }
    ]
    networkProfile: {
      networkPolicy: 'cilium'
      podCidr: podCidr
    }
    linuxProfile: {
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
    // Single-node clusters do not need an infrastructure logical network; include it
    // only when a logicalNetworkId is supplied (multi-node / IP-pool scenarios).
    cloudProviderProfile: empty(logicalNetworkId) ? null : {
      infraNetworkProfile: {
        vnetSubnetIds: [
          logicalNetworkId
        ]
      }
    }
    licenseProfile: {
      azureHybridBenefit: 'NotApplicable'
    }
  }
}

output connectedClusterName string = connectedCluster.name
output connectedClusterId string = connectedCluster.id
output provisionedClusterInstanceId string = provisionedClusterInstance.id
output connectCommand string = 'az connectedk8s proxy --name ${connectedCluster.name} --resource-group ${resourceGroup().name}'
output apiVersions object = {
  connectedClusters: connectedClusterApiVersion
  provisionedClusterInstances: provisionedClusterApiVersion
}
