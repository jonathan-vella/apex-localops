using './main.bicep'

// =============================================================================
// apex-localops — Azure Local SELF-HOSTED profile parameters.
// Public-safe by construction: NO tenant-specific GUIDs and NO secrets are
// committed here. scripts/deploy-selfhosted.sh reads the Windows password from
// LOCALSELF_ADMIN_PASSWORD and resolves the deployer + Azure Local RP object ids
// at deploy time. See docs/selfhosted/quickstart.md.
// =============================================================================

// --- Windows credentials: password is NEVER stored in this file ---
// Read from the LOCALSELF_ADMIN_PASSWORD environment variable at deploy time.
// Use scripts/deploy-selfhosted.sh, which prompts for it securely (no echo, no disk write).
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = readEnvironmentVariable('LOCALSELF_ADMIN_PASSWORD', '')

// --- Region & naming ---
// Infra region. NOTE: the Azure Local INSTANCE region is a separate parameter
// (azureLocalInstanceLocation) because not every region supports the instance.
param location = 'swedencentral'
param namePrefix = 'ApexLocal'

// --- Cluster host (nested-virtualization) ---
// E64s_v6 (64 vCPU / 512 GB) hosts a 3-node cluster (3 x 96 GB nodes + a DC).
// Drop to E32s_v6 for a 2-node cluster (set clusterNodeCount = 2).
param hostVmSize = 'Standard_E64s_v6'
param hostDataDiskCount = 12
param hostDataDiskSizeGB = 256

// --- Azure Local cluster shape ---
//   3 nodes  => odd quorum, no witness (default)
//   2 nodes  => cloud witness required (configure in artifacts/selfhosted/azlocal.json)
param clusterNodeCount = 3
param nodeMemoryMB = 98304
param nodeCpuCount = 16
param clusterName = 'apexlocal-cluster'
// swedencentral is NOT supported for the Azure Local instance; register it in westeurope.
param azureLocalInstanceLocation = 'westeurope'

// --- Azure Hybrid Benefit (ON by default for this project) ---
param enableAzureHybridBenefit = true

// --- Connectivity: Bastion ON => no public IP on the VMs; NAT Gateway egress ---
param deployBastion = true
param vmAutologon = true

// --- Acquisition / management jumpbox (Windows Server 2025, reached via Bastion) ---
// The operator's in-Azure workstation for the one manual step: download the two
// ISOs and upload them to the storage account with Upload-Isos.ps1.
param deployManagementVm = true
param managementVmSize = 'Standard_D4s_v5'

// --- Observability + artifact source (self-hosted in this repo) ---
// Pin githubBranch to a release tag (e.g. 'v1.0.0') for reproducible deploys.
param logAnalyticsWorkspaceName = 'ApexLocal-Workspace'
param isoContainerName = 'iso-images'
param logsContainerName = 'logs'
param githubAccount = 'jonathan-vella'
param githubRepo = 'apex-localops'
param githubBranch = 'main'

// --- Identity inputs (resolved at deploy time; never committed) ---
// deployerPrincipalId  : signed-in user/SP object id -> Storage Blob Data Owner (ISO upload).
// hciResourceProviderObjectId : object id of app 1412d89f-b8a8-4111-b4fd-e82905cbd85d in your
//                               tenant -> required by the in-VM cluster deploy.
// Both are resolved by scripts/deploy-selfhosted.sh; leave empty for a what-if.
param deployerPrincipalId = readEnvironmentVariable('LOCALSELF_DEPLOYER_PRINCIPAL_ID', '')
param deployerPrincipalType = 'User'
param hciResourceProviderObjectId = readEnvironmentVariable('LOCALSELF_HCI_RP_OBJECT_ID', '')

// --- Tagging: governResourceTags=false (not a Microsoft-internal lab tenant) ---
param governResourceTags = false
param tags = {
  Project: 'apex_localselfhosted'
}
