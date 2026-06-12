# Deploy a Windows Server 2025 VM on Azure Local with Bicep

A self-contained, copy-paste demo that deploys **one Windows Server 2025 virtual machine** onto an
operational Azure Local (Azure Arc) instance using a single Bicep template — correctly sized,
guest-agent enabled, and optionally AD domain-joined.

## What it deploys

`main.bicep` creates, in dependency order:

| # | Resource | Purpose |
|---|----------|---------|
| 1 | `Microsoft.HybridCompute/machines` | The Arc machine (SystemAssigned identity) for zero-touch guest-agent onboarding |
| 2 | `Microsoft.AzureStackHCI/networkInterfaces` | A NIC on an existing logical network (auto IP from the pool/DHCP) |
| 3 | `Microsoft.AzureStackHCI/virtualHardDisks` | Optional data disk(s) |
| 4 | `Microsoft.AzureStackHCI/virtualMachineInstances` | The sized VM (`hardwareProfile.vmSize = 'Custom'`) |
| 5 | `Microsoft.HybridCompute/machines/extensions` | Optional AD domain join (`JsonADDomainExtension`) |

> **The one thing people get wrong:** Azure Local sizes a VM via
> `hardwareProfile = { vmSize: 'Custom', processors: <n>, memoryMB: <mb> }`. You **must** set
> `vmSize: 'Custom'`. Omitting it — or using an Azure VM SKU name like `Standard_D2s_v3` through the
> CLI — produces an unbootable **0-CPU / 0-MB** VM whose guest agent never installs. This template
> always sets `vmSize: 'Custom'`.

## Prerequisites

- An operational Azure Local instance (23H2+) with its Arc Resource Bridge and custom location.
- A **VM image** already created on the cluster (for example `2025-datacenter-azure-edition-01`).
- A **logical network** already created (for example `localbox-vm-lnet-vlan200`).
- Azure CLI with the `stack-hci-vm` extension (used by the verify/cleanup commands):

```bash
az extension add --name stack-hci-vm
az extension add --name customlocation
```

## Files

| File | Purpose |
|------|---------|
| `deploy.sh` | One-command CLI wrapper (password, preflight, what-if, deploy, verify, cleanup). |
| `main.bicep` | The VM template (parameterized). |
| `main.bicepparam` | Example values for a Windows Server 2025 VM; password via environment variable. |

## Fastest path: `deploy.sh`

The script wraps everything below into one command. From this folder:

```bash
cd infra/bicep/azlocal-vm
az login                                  # once
export LOCALBOX_ADMIN_PASSWORD='<strong-password>'   # or let the script prompt
./deploy.sh                               # preflight + confirm + deploy + verify
```

By default the VM is named **`ws2025-<random>`** (e.g. `ws2025-3f9a`), so repeated demo runs
never clash. The resolved name is printed before the deploy and again on success.

Common variations:

```bash
./deploy.sh --what-if                     # preview only, no changes
./deploy.sh --yes                         # skip the confirmation prompt
./deploy.sh --prefix ws25demo             # base name -> ws25demo-<random>
./deploy.sh --suffix lab1                 # pin the suffix -> ws2025-lab1
./deploy.sh --no-suffix --prefix ws2025   # exact name ws2025 (no random part)
./deploy.sh --name demo-ws2025-02         # fully explicit name (no suffix added)
./deploy.sh --domain-join                 # also AD-join (default jumpstart.local / Administrator)
./deploy.sh --domain-join --domain contoso.local --domain-user joiner
./deploy.sh -g my-rg                      # target a different resource group
./deploy.sh --cleanup --name ws2025-lab1  # delete that VM + its NIC + data disk
./deploy.sh --help                        # all options
```

> The final VM name must be **<= 15 characters** (NetBIOS / domain-join limit); the script
> rejects anything longer. `--cleanup` requires an exact `--name` (random names can't be guessed).

Prefer to run the raw `az` commands yourself? The manual steps follow.

## Quick start (manual)

### 1. Sign in and choose the subscription

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Provide the admin password (never stored on disk)

```bash
export LOCALBOX_ADMIN_PASSWORD='<choose-a-strong-password>'
```

### 3. (Optional) Lint the template

```bash
cd infra/bicep/azlocal-vm
az bicep build --file main.bicep
```

### 4. Preview the deployment (no changes)

```bash
RG=rg-azlocal-swc01
az deployment group what-if \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### 5. Deploy the VM

```bash
RG=rg-azlocal-swc01
az deployment group create \
  --resource-group "$RG" \
  --name "ws2025-demo-$(date +%Y%m%d-%H%M%S)" \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### 6. Verify the result

The Azure Local VM instance readback shows the real sizing and power state
(`az stack-hci-vm show --query` returns empty for these resources, so query the ARM REST path):

```bash
RG=rg-azlocal-swc01
SUB=$(az account show --query id -o tsv)
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.HybridCompute/machines/demo-ws2025-01/providers/Microsoft.AzureStackHCI/virtualMachineInstances/default?api-version=2024-01-01" \
  --query "{provisioningState:properties.provisioningState, vmSize:properties.hardwareProfile.vmSize, cpu:properties.hardwareProfile.processors, memoryMB:properties.hardwareProfile.memoryMB, power:properties.status.powerState}" \
  -o jsonc
```

Expect `vmSize: "Custom"`, `cpu: 2`, `memoryMB: 8192`, `power: "Running"`.

## Optional: join an Active Directory domain

The template joins a domain when `domainToJoin` is set, via the `JsonADDomainExtension` (no in-guest
script needed). The VM restarts automatically after joining. Either uncomment the domain block in
`main.bicepparam`, or pass the domain parameters inline using the full inline-parameter form below.

### Deploy + domain join with inline parameters

This form takes no `.bicepparam` file, so you can add or change any parameter freely:

```bash
RG=rg-azlocal-swc01
az deployment group create \
  --resource-group "$RG" \
  --name "ws2025-demo-$(date +%Y%m%d-%H%M%S)" \
  --template-file main.bicep \
  --parameters \
      name=demo-ws2025-01 \
      location=westeurope \
      vCPUCount=2 \
      memoryMB=8192 \
      adminUsername=arcdemo \
      adminPassword="$LOCALBOX_ADMIN_PASSWORD" \
      imageName=2025-datacenter-azure-edition-01 \
      isMarketplaceImage=true \
      hciLogicalNetworkName=localbox-vm-lnet-vlan200 \
      customLocationName=jumpstart \
      dataDiskParams='[{"name":"demo-ws2025-01-data","diskSizeGB":128,"dynamic":true}]' \
      domainToJoin=jumpstart.local \
      domainJoinUserName=Administrator \
      domainJoinPassword="$LOCALBOX_ADMIN_PASSWORD"
```

### Confirm the join succeeded

```bash
RG=rg-azlocal-swc01
SUB=$(az account show --query id -o tsv)
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.HybridCompute/machines/demo-ws2025-01/extensions/domainJoinExtension?api-version=2025-01-13" \
  --query "{state:properties.provisioningState, message:properties.instanceView.status.message}" \
  -o jsonc
```

Expect `state: "Succeeded"` and a message such as `Join completed for Domain 'jumpstart.local'`.

## Clean up

Delete the VM and its dependent resources (NIC and data disk are not removed with the VM):

```bash
RG=rg-azlocal-swc01
az stack-hci-vm delete            -g "$RG" --name demo-ws2025-01      --yes
az stack-hci-vm network nic delete -g "$RG" --name demo-ws2025-01-nic  --yes
az stack-hci-vm disk delete       -g "$RG" --name demo-ws2025-01-data --yes
```

## Parameter reference

| Parameter | Default | Notes |
|-----------|---------|-------|
| `name` | `demo-ws2025-01` | VM + computer name; <= 15 chars. |
| `location` | resource group location | Azure region the instance is registered in (for example `westeurope`). |
| `vCPUCount` | `2` | Virtual processors. |
| `memoryMB` | `8192` | Memory in MB (multiple of 4). |
| `adminUsername` | `arcdemo` | In-guest local administrator. |
| `adminPassword` | — | `@secure()`; supply via `readEnvironmentVariable('LOCALBOX_ADMIN_PASSWORD')`. |
| `imageName` | — | Existing gallery image name on the cluster. |
| `isMarketplaceImage` | `true` | `false` for a custom gallery image. |
| `hciLogicalNetworkName` | — | Existing logical network name. |
| `customLocationName` | — | Custom location name of the Azure Local instance. |
| `storagePathId` | `''` | CSV storage container resource ID; empty = automatic placement. |
| `dataDiskParams` | `[]` | Array of `{ name, diskSizeGB, dynamic }`. |
| `domainToJoin` | `''` | AD FQDN to join; empty = no join. |
| `domainTargetOu` | `''` | Optional OU path. |
| `domainJoinUserName` | `''` | Domain account (without domain prefix). Required when joining. |
| `domainJoinPassword` | `''` | `@secure()`; required when joining. |

## How it works (key facts)

- **Sizing at create:** `hardwareProfile.vmSize` is fixed to `'Custom'` so `processors` and `memoryMB`
  are honored. This is the reliable mechanism for Azure Local VM sizing.
- **Guest agent:** the Arc machine is created with a system-assigned identity and the VM sets
  `provisionVMAgent` / `provisionVMConfigAgent`, so the guest agent onboards automatically.
- **Domain join:** done declaratively by the `JsonADDomainExtension` — no fragile in-guest run-command.
- **Idempotent:** re-running the deployment is safe; ARM no-ops unchanged resources.
- **API versions (latest GA):** AzureStackHCI types `2024-01-01`; HybridCompute `2025-01-13`.

Adapted from the Microsoft sample
[vm-windows-disks-and-adjoin](https://aka.ms/hci-vmbiceptemplate).
