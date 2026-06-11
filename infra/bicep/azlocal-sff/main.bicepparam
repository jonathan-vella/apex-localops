using './main.bicep'

// =============================================================================
// apex-localops — Azure Local Small Form Factor (SFF) parameters.
// Public-safe by construction: NO tenant-specific GUIDs and NO secrets are
// committed here. scripts/deploy-sff.sh reads the Windows password from the
// LOCALSFF_ADMIN_PASSWORD environment variable at deploy time. See docs/sff-quickstart.md.
// =============================================================================

// --- Windows credentials: password is NEVER stored in this file ---
// Read from the LOCALSFF_ADMIN_PASSWORD environment variable at deploy time.
// Use scripts/deploy-sff.sh, which prompts for it securely (no echo, no disk write).
param windowsAdminUsername = 'arcdemo'
param windowsAdminPassword = readEnvironmentVariable('LOCALSFF_ADMIN_PASSWORD', '')

// --- Region & naming ---
// The host VM, jumpbox, VNet, Bastion, NAT, Key Vault, and staging storage live in this
// region (rg-sff-host-swc01). Sweden Central has the nested-virt VM capacity East US
// currently restricts. The Azure Local site + edge machine are provisioned separately into
// an East US resource group (rg-sff-azl-eus01) — AKS on bare metal is East US only.
param location = 'swedencentral'
param namePrefix = 'LocalSFF'

// --- Host (nested-virtualization Hyper-V) ---
// Standard_D8s_v5 (8 vCPU / 32 GB) comfortably hosts one 16 GB / 4 vCPU nested
// ROE test VM. Bump to an E-series SKU for extra RAM headroom.
param hostVmSize = 'Standard_D8s_v5'
param hostDataDiskSizeGB = 512

// --- Azure Hybrid Benefit (ON by default for this project) ---
// Applies AHB across the SFF profile: Windows_Server on the host VM and
// Windows_Client on the Windows 11 jumpbox (matches the LocalBox profile). Removes the
// Windows license charge; requires the corresponding eligible licenses. Set false for
// license-included (PAYG) billing on both VMs.
param enableAzureHybridBenefit = true

// --- Connectivity: Bastion ON => no public IP on the VMs; NAT Gateway egress ---
param deployBastion = true
param vmAutologon = true
param natDNS = '8.8.8.8'

// --- Optional Windows 11 acquisition / management jumpbox (reached via Bastion) ---
param deployManagementVm = true
param managementVmSize = 'Standard_D4s_v5'

// --- Nested SFF test VM (fixed to satisfy the Learn "Review your VM setup" gate) ---
//   Generation 2 · TPM ON · Secure Boot OFF · >= 4 vCPU · 16000 MB · 256 GB VHD
param nestedVmName = 'linuxsff-vm'
param nestedVmMemoryMB = 16000
param nestedVmCpuCount = 4
param nestedVmDiskGB = 256

// --- Internal Hyper-V NAT network (created on the host by set-network.ps1) ---
param hvSwitchName = 'HV-Internal-NAT'
param hvSubnetPrefix = '192.168.200.0/24'
param hvGateway = '192.168.200.1'

// --- Observability + artifact source (self-hosted in this repo) ---
// Pin githubBranch to a release tag (e.g. 'v1.0.0') for reproducible deploys.
param logAnalyticsWorkspaceName = 'LocalSFF-Workspace'
param stagingArtifactsContainer = 'sff-artifacts'
param githubAccount = 'jonathan-vella'
param githubRepo = 'apex-localops'
param githubBranch = 'main'

// --- Tagging: governResourceTags=false (not a Microsoft-internal lab tenant) ---
param governResourceTags = false
param tags = {
  Project: 'apex_localsff'
}

// --- Operator data-plane access to the staging account ---
// Granting Storage Blob Data Contributor to the deploying user lets them stage the ROE ISO +
// Configurator App via the Azure portal blob browser (Owner/Contributor are control-plane only
// and do NOT grant blob data access). scripts/deploy-sff.sh resolves the signed-in user's object
// id into LOCALSFF_OPERATOR_PRINCIPAL_ID; leave empty to skip (the jumpbox MI path still works).
param operatorPrincipalId = readEnvironmentVariable('LOCALSFF_OPERATOR_PRINCIPAL_ID', '')
param operatorPrincipalType = 'User'
