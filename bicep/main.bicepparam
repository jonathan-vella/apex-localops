using './main.bicep'

// =============================================================================
// apex-localops parameters - Sweden Central LocalBox / Azure Local deployment.
// Public-safe by construction: NO tenant-specific GUIDs and NO secrets are
// committed here. scripts/deploy.sh resolves tenantId + spnProviderId at deploy
// time and passes them as -p overrides; the Windows password is read from the
// LOCALBOX_ADMIN_PASSWORD environment variable. See README.md.
// =============================================================================

// --- Identity: resolved from the environment (public repo => no GUIDs committed).
//     scripts/deploy.sh resolves and exports these before deploying:
//       LOCALBOX_TENANT_ID        <- az account show --query tenantId
//       LOCALBOX_SPN_PROVIDER_ID  <- check-providers.sh (Microsoft.AzureStackHCI RP id)
//     To deploy manually, export both vars first (see README).
param tenantId = readEnvironmentVariable('LOCALBOX_TENANT_ID', '')
param spnProviderId = readEnvironmentVariable('LOCALBOX_SPN_PROVIDER_ID', '')

// --- Windows credentials: password is NEVER stored in this file ---
// It is read from the LOCALBOX_ADMIN_PASSWORD environment variable at deploy time.
// Use scripts/deploy.sh, which prompts for it securely (no echo, no disk write).
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = readEnvironmentVariable('LOCALBOX_ADMIN_PASSWORD', '')

// --- Regions: infra in Sweden Central, Azure Local registered in West Europe ---
// (swedencentral is NOT a supported Azure Local region; westeurope is the EU option.)
param location = 'swedencentral'
param azureLocalInstanceLocation = 'westeurope'

// --- Client VM (data disks default to the P30 tier in host/host.bicep) ---
param vmSize = 'Standard_E32s_v6'
param enableAzureSpotPricing = false

// --- Connectivity: Bastion ON => no public IP on the VM; NAT Gateway egress ---
param deployBastion = true
param rdpPort = '3389'
param vmAutologon = true

// --- Cluster automation ---
param autoDeployClusterResource = true
param autoUpgradeClusterResource = false

// --- Windows 11 management/jumpbox VM (reached via Bastion) ---
param deployManagementVm = true
param managementVmSize = 'Standard_D4s_v5'

// --- Observability + artifact source (self-hosted in this repo) ---
// Pin githubBranch to a release tag (e.g. 'v1.0.0') for reproducible deploys.
param logAnalyticsWorkspaceName = 'LocalBox-Workspace'
param natDNS = '8.8.8.8'
param githubAccount = 'jonathan-vella'
param githubRepo = 'apex-localops'
param githubBranch = 'main'

// --- Tagging: governResourceTags=false (not a Microsoft-internal lab tenant) ---
param governResourceTags = false
param tags = {
  Project: 'jumpstart_LocalBox'
}
