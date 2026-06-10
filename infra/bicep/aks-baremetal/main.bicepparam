using './main.bicep'

// =============================================================================
// apex-localops — AKS on bare metal (preview) parameters.
// Public-safe by construction: NO tenant-specific GUIDs and NO secrets are
// committed here. scripts/deploy-aks-baremetal.sh resolves the tenant-specific
// values from environment variables at deploy time:
//
//   AKSBM_CUSTOM_LOCATION_ID  <- ARM id of the SFF edge machine's custom location
//   AKSBM_CONTROL_PLANE_IP    <- a reserved IP in the machine's subnet (not the host IP)
//   AKSBM_SSH_PUBLIC_KEY      <- contents of your SSH public key (e.g. ~/.ssh/id_rsa.pub)
//   AKSBM_ADMIN_GROUP_ID      <- Entra security group object id for cluster admins
//
// To deploy manually, export those vars first (see docs/aks-baremetal-quickstart.md).
// =============================================================================

param clusterName = 'localsff-aks'

// AKS on bare metal public preview is East US only.
param location = 'eastus'

// Kubernetes version (preview: 1.34.2 or 1.34.3).
param kubernetesVersion = '1.34.3'

// --- Tenant-specific values, resolved from the environment (no GUIDs committed) ---
param customLocationId = readEnvironmentVariable('AKSBM_CUSTOM_LOCATION_ID', '')
param controlPlaneIP = readEnvironmentVariable('AKSBM_CONTROL_PLANE_IP', '')
param sshPublicKey = readEnvironmentVariable('AKSBM_SSH_PUBLIC_KEY', '')
param adminGroupObjectId = readEnvironmentVariable('AKSBM_ADMIN_GROUP_ID', '')

// --- Cluster shape (single-node preview defaults) ---
param enableAzureRBAC = true
param podCidr = '10.244.0.0/16'
param agentNodeCount = 1
param agentPoolName = 'nodepool1'

// Single-node clusters do not need a logical network; leave empty.
param logicalNetworkId = ''

param tags = {
  Project: 'apex_localsff'
  Workload: 'aks-baremetal'
}
