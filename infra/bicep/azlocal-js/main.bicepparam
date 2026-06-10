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

// --- Cluster topology PROFILE ----------------------------------------------------------
// Default = 3-node, NO witness, E64 host. Pick one profile (keep the three values aligned):
//
//   3-node (default, witnessless — best when storage shared-key access is restricted):
//     clusterNodeCount = 3 ; vmSize = 'Standard_E64s_v6' ; dataDiskCount = 12
//
//   2-node (cloud witness — only where storage shared-key access is ALLOWED; a
//   `Deny allowSharedKeyAccess` policy will fail the cloud-witness validation):
//     clusterNodeCount = 2 ; vmSize = 'Standard_E32s_v6' ; dataDiskCount = 8
//
// Override per deploy without editing this file, e.g.:
//   az deployment group create ... -p clusterNodeCount=2 vmSize=Standard_E32s_v6 dataDiskCount=8
param clusterNodeCount = 3
param vmSize = 'Standard_E64s_v6'
param dataDiskCount = 12
param enableAzureSpotPricing = false

// --- Connectivity: Bastion ON => no public IP on the VM; NAT Gateway egress ---
param deployBastion = true
param rdpPort = '3389'
param vmAutologon = true

// --- Cluster automation ---
param autoDeployClusterResource = true
param autoUpgradeClusterResource = false

// --- Azure Local node OS image ---------------------------------------------------------
// 'latest' (default) auto-installs the newest published AzLocalYYMM image at deploy time,
// so each build gets the latest-and-greatest release. To PIN a release for reproducible
// builds, set the full VHDX URL, e.g.:
//   param azureLocalImageUrl = 'https://azlocalvhds.blob.core.windows.net/images/AzLocal2604.vhdx'
param azureLocalImageUrl = 'latest'

// --- Windows Server image for the nested AzLMGMT management VMs (DC, router, WAC) -------
// Default = Windows Server 2022 (WinServerApril2024). To run the management VMs on a
// different Server build, set a full VHDX URL - e.g. Windows Server 2025:
//   param windowsServerImageUrl = 'https://azlocalvhds.blob.core.windows.net/images/ArcBox-Win2K25.vhdx'
// NOTE: only the default (Server 2022) image is validated with the management-VM build
// automation (AD DS / RRAS / Windows Admin Center). Other images may work but are untested.
param windowsServerImageUrl = 'https://jumpstartprodsg.blob.core.windows.net/hcibox23h2/WinServerApril2024.vhdx'

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
