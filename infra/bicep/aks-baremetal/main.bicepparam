using './main.bicep'

// =============================================================================
// apex-localops — AKS on bare metal (preview) parameters.
// Public-safe by construction: NO tenant-specific GUIDs and NO secrets are
// committed here. scripts/deploy-aks-baremetal.sh resolves the tenant-specific
// values from environment variables at deploy time:
//
//   AKSBM_EDGE_MACHINE_NAME         <- name of the Provisioned SFF EdgeMachine (this RG)
//   AKSBM_CONTROL_PLANE_IP          <- a reserved IP in the machine's subnet (not the host IP)
//   AKSBM_SSH_PUBLIC_KEY            <- contents of your SSH public key (e.g. ~/.ssh/id_rsa.pub)
//   AKSBM_ADMIN_GROUP_ID            <- Entra security group object id for cluster admins
//   AKSBM_KUBERNETES_VERSION        <- (optional) overrides the default K8s version
//   AKSBM_LOG_ANALYTICS_WORKSPACE_ID<- (optional) workspace ARM id for container monitoring
//
// To deploy manually, export those vars first (see docs/sff/aks-baremetal.md).
// =============================================================================

param clusterName = 'localsff-aks'

// AKS on bare metal public preview is East US only.
param location = 'eastus'

// Kubernetes version — free-form, date-suffixed per the preview (e.g. 1.34.3-20260204).
// Overridable via AKSBM_KUBERNETES_VERSION as the preview revs versions frequently.
param kubernetesVersion = readEnvironmentVariable('AKSBM_KUBERNETES_VERSION', '1.34.3-20260204')

// --- Tenant-specific values, resolved from the environment (no GUIDs committed) ---
param edgeMachineName = readEnvironmentVariable('AKSBM_EDGE_MACHINE_NAME', '')
param controlPlaneIp = readEnvironmentVariable('AKSBM_CONTROL_PLANE_IP', '')
param sshPublicKey = readEnvironmentVariable('AKSBM_SSH_PUBLIC_KEY', '')
// adminGroupObjectIds is an array; wrap the single resolved object id (empty => []).
param adminGroupObjectIds = empty(readEnvironmentVariable('AKSBM_ADMIN_GROUP_ID', ''))
  ? []
  : [
      readEnvironmentVariable('AKSBM_ADMIN_GROUP_ID', '')
    ]

// --- Access ---
param enableAzureRbac = true

// --- Integrations (portal parity: both on by default; monitoring is skipped unless a
// Log Analytics workspace id is supplied) ---
param enableAzurePolicy = true
param enableContainerMonitoring = true
param logAnalyticsWorkspaceId = readEnvironmentVariable('AKSBM_LOG_ANALYTICS_WORKSPACE_ID', '')

param tags = {
  Project: 'apex_localsff'
  Workload: 'aks-baremetal'
}
