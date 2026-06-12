// Azure Local Arc VMs — at-scale orchestrator.
//
// Deploys N VMs by invoking azlocal-vm.bicep once per entry in the `vms` array.
// This is the "at scale" pattern: one module instance per VM, each producing its
// own Arc machine + NIC + (optional) data disks + virtualMachineInstance.
//
// Docs: docs/upstream/azure-local/manage/create-arc-virtual-machines.md (Bicep tab)
//
// Deploy (provide the admin password via env var — never commit secrets):
//   export AZLOCAL_VM_ADMIN_PASSWORD='<password>'
//   az deployment group create \
//     --resource-group <rg> \
//     --template-file main.bicep \
//     --parameters main.sample.bicepparam

@description('Optional vCPU/memory/disk overrides per VM.')
type vmSpecType = {
  @description('VM name (<= 15 chars for Windows).')
  @maxLength(15)
  name: string

  @description('Optional. vCPU count. Defaults to 2.')
  vCpuCount: int?

  @description('Optional. Memory in MB. Defaults to 8192.')
  memoryMB: int?

  @description('Optional. Data disks for this VM.')
  dataDisks: dataDiskType[]?
}

@description('A data disk specification.')
type dataDiskType = {
  @description('Size of the data disk in GB.')
  diskSizeGB: int

  @description('Optional. True for a dynamically expanding disk.')
  dynamic: bool?
}

@description('Azure region of the Azure Local instance resources.')
param location string = resourceGroup().location

@description('Name of the custom location for the Azure Local instance.')
param customLocationName string

@description('Name of an existing logical network on the Azure Local instance.')
param logicalNetworkName string

@description('Name of an existing VM image on the Azure Local instance.')
param imageName string

@description('Set true when imageName is an Azure Marketplace gallery image.')
param isMarketplaceImage bool = true

@description('Local administrator username applied to every VM.')
param adminUsername string

@secure()
@description('Local administrator password applied to every VM.')
param adminPassword string

@description('The set of VMs to create. Each entry becomes one Arc VM.')
param vms vmSpecType[]

module vm 'azlocal-vm.bicep' = [
  for spec in vms: {
    name: 'deploy-${spec.name}'
    params: {
      name: spec.name
      location: location
      vCpuCount: spec.?vCpuCount ?? 2
      memoryMB: spec.?memoryMB ?? 8192
      adminUsername: adminUsername
      adminPassword: adminPassword
      imageName: imageName
      isMarketplaceImage: isMarketplaceImage
      logicalNetworkName: logicalNetworkName
      customLocationName: customLocationName
      dataDisks: spec.?dataDisks ?? []
    }
  }
]

@description('Resource IDs of every VM created.')
output vmResourceIds array = [for (spec, i) in vms: vm[i].outputs.vmResourceId]
