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
// Use scripts/deploy-selfhosted.sh, which requires it in the process environment.
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = readEnvironmentVariable('LOCALSELF_ADMIN_PASSWORD')

// --- Region & naming ---
// Infra region. NOTE: the Azure Local INSTANCE region is a separate parameter
// (azureLocalInstanceLocation) because not every region supports the instance.
param location = 'swedencentral'
param namePrefix = 'ApexLocal'

// --- Fixed Azure Local evaluation shape ---
// The release contract is 3 x 96 GB / 16-vCPU nodes on E64s_v6 with 12 x 256 GB
// P30 host disks. These values are intentionally not public deployment parameters.
param clusterName = 'apexlocal'

// --- Azure Hybrid Benefit (ON by default for this project) ---
param enableAzureHybridBenefit = true

// --- Connectivity: Bastion ON => no public IP on the VMs; NAT Gateway egress ---
param deployBastion = true

// --- Acquisition / management jumpbox (Windows Server 2025, reached via Bastion) ---
// The operator's in-Azure workstation for the one manual step: download the two
// ISOs and upload them to the storage account with Upload-Isos.ps1.
param deployManagementVm = true
param managementVmSize = 'Standard_D4s_v5'

// --- Observability + artifact source (self-hosted in this repo) ---
// The candidate defaults to the reserved release tag. Golden validation overrides
// this with the immutable candidate commit SHA.
param logAnalyticsWorkspaceName = 'ApexLocal-Workspace'
param isoContainerName = 'iso-images'
param logsContainerName = 'logs'
// Fork override: export GITHUB_ACCOUNT/GITHUB_REPO to serve runtime artifacts from your fork.
param githubAccount = readEnvironmentVariable('GITHUB_ACCOUNT', 'jonathan-vella')
param githubRepo = readEnvironmentVariable('GITHUB_REPO', 'apex-localops')
param artifactRef = 'v1.3.0-rc.1'

// --- Identity input (resolved at deploy time; never committed) ---
// hciResourceProviderObjectId : object id of app 1412d89f-b8a8-4111-b4fd-e82905cbd85d in your
//                               tenant -> required by the in-VM cluster deploy.
param hciResourceProviderObjectId = readEnvironmentVariable('LOCALSELF_HCI_RP_OBJECT_ID', '')

// --- Tagging: governResourceTags=false (not a Microsoft-internal lab tenant) ---
param governResourceTags = false
param tags = {
  Project: 'apex_localselfhosted'
}
