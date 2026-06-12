# Logical networks & NSGs — Azure CLI cheat-sheet

> Grounded in the vendored Microsoft docs:
> [docs/upstream/azure-local/manage/create-logical-networks.md](../../../../docs/upstream/azure-local/manage/create-logical-networks.md)
> and [docs/upstream/azure-local/manage/create-network-security-groups.md](../../../../docs/upstream/azure-local/manage/create-network-security-groups.md).
> Commands use the `stack-hci-vm` Azure CLI extension. Treat Microsoft Learn as canonical when the
> weekly mirror lags.

Install/upgrade the extension first: `az extension add -n stack-hci-vm --upgrade`.

## Logical network (LNET)

A logical network maps Azure Local VM NICs onto a host VM switch. VMs require an existing LNET
(the `azlocal-vm-management` Bicep references one by name).

### Shared parameters

```azurecli
$lnetName = "mylocal-lnet-static"
$vmSwitchName = '"ConvergedSwitch(management_compute_storage)"'  # default switch: double-quote inside single-quote
$subscription = "<Subscription ID>"
$resource_group = "mylocal-rg"
$customLocationName = "mylocal-cl"
$customLocationID = "/subscriptions/$subscription/resourceGroups/$resource_group/providers/Microsoft.ExtendedLocation/customLocations/$customLocationName"
$location = "eastus"
$addressPrefixes = "100.68.180.0/28"
$gateway = "192.168.200.1"
$dnsServers = "192.168.200.222"
$vlan = "201"
```

### Static LNET (required for static-IP VMs; gateway + DNS + VLAN mandatory)

```azurecli
az stack-hci-vm network lnet create --subscription $subscription --resource-group $resource_group --custom-location $customLocationID --location $location --name $lnetName --vm-switch-name $vmSwitchName --ip-allocation-method "Static" --address-prefixes $addressPrefixes --gateway $gateway --dns-servers $dnsServers --vlan $vlan
```

### DHCP (dynamic) LNET

```azurecli
az stack-hci-vm network lnet create --subscription $subscription --resource-group $resourceGroup --custom-location $customLocationID --location $location --name $lnetName --vm-switch-name $vSwitchName --ip-allocation-method "Dynamic"
```

## Network security groups (NSGs)

> An NSG must have at least one rule. An empty NSG denies all inbound traffic, making any associated
> VM or LNET unreachable.

### Create an NSG

```azurecli
$resource_group = "examplerg"
$nsgname = "examplensg"
$customLocationId = "/subscriptions/<Subscription ID>/resourcegroups/examplerg/providers/microsoft.extendedlocation/customlocations/examplecl"
$location = "eastus"

az stack-hci-vm network nsg create -g $resource_group --name $nsgname --custom-location $customLocationId --location $location
```

### Inbound rule (priority 100–4096; lower = higher priority)

```azurecli
$securityrulename = "examplensr"
$sportrange = "*"
$saddprefix = "10.0.0.0/24"
$dportrange = "80"
$daddprefix = "192.168.99.0/24"
$description = "Inbound security rule"

az stack-hci-vm network nsg rule create -g $resource_group --nsg-name $nsgname --name $securityrulename --priority 400 --custom-location $customLocationId --access "Deny" --direction "Inbound" --location $location --protocol "*" --source-port-ranges $sportrange --source-address-prefixes $saddprefix --destination-port-ranges $dportrange --destination-address-prefixes $daddprefix --description $description
```

### Outbound rule

```azurecli
az stack-hci-vm network nsg rule create -g $resource_group --nsg-name $nsgname --name $securityrulename --priority 500 --custom-location $customLocationId --access "Deny" --direction "Outbound" --location $location --protocol "*" --source-port-ranges $sportrange --source-address-prefixes $saddprefix --destination-port-ranges $dportrange --destination-address-prefixes $daddprefix --description $description
```

Tip: append `-h` to any command (for example `az stack-hci-vm network nsg create -h`) for inline help.
