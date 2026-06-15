# SFF overview

[Documentation home](../README.md) / SFF / Overview

The Small Form Factor (SFF) profile builds an Azure Local edge test environment inside a single
Azure VM — no physical edge hardware. A nested-virtualization Hyper-V host builds the SFF
Maintenance OS (ROE) test VM inside itself and drives it to a successful setup. At roughly
one-tenth the cost of the cluster profiles, it is the lightest way to evaluate edge scenarios,
and it is the only path to AKS on bare metal.

This page explains the topology and what gets deployed. To deploy, go to the
[SFF quickstart](quickstart.md).

> [!IMPORTANT]
> SFF on a VM is for **testing and evaluation only** — Microsoft does not support it for
> production. Production SFF must run on
> [validated hardware](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview#supported-devices).
> SFF is in **preview**; flows and artifact names may change.

## When to use this profile

Choose SFF when you want to evaluate an edge or Small Form Factor device, or when you need a
target for AKS on bare metal. If you want a full multi-node cluster, use the
[LocalBox profile](../localbox/overview.md) or the
[Self-hosted profile](../selfhosted/overview.md) instead. For a full comparison, see
[Choose a profile](../choose-a-profile.md).

## Architecture

The profile deploys one nested-virtualization host VM into a Bastion-only resource group. The
host builds one or two Gen2 ROE test VMs inside itself, on an isolated internal network.

```mermaid
flowchart TB
    User(["Operator"])
    subgraph RG["resource group rg-azlocal-sff-eus01"]
        Bastion["Azure Bastion"]
        NAT["NAT Gateway"]
        KV["Key Vault<br/>ownership voucher"]
        SA["Staging Storage<br/>roe.iso · configurator.msi"]
        Jump["LocalSFF-Mgmt<br/>Win11 jumpbox (optional)"]
        subgraph Host["LocalSFF-Host · Standard_D8s_v5 · Hyper-V"]
            subgraph HVNet["HV-Internal-NAT · 192.168.200.0/24"]
                Nested["SFF test VM (Gen2)<br/>TPM on · SBoot off · 4 vCPU · 16 GB · 256 GB<br/>boots Maintenance OS (ROE)"]
            end
        end
    end
    User -->|HTTPS via portal| Bastion
    Bastion --> Jump
    Bastion --> Host
    Jump -->|portal Download all → upload| SA
    Host -->|managed identity: pull ISO+MSI| SA
    Host -->|store .pem| KV
    Nested -. IMDS 169.254.169.254 DENY .-> Host
```

**Diagram key:** solid arrows are network and data paths through Azure Bastion and the host's
managed identity; the dotted arrow is the denied path to the Instance Metadata Service (IMDS),
which the host blocks for the nested VM.

## What it deploys

- A `LocalSFF-Host` nested-virtualization VM (`Standard_D8s_v5` by default) that builds one or
  two Gen2 ROE test VMs (TPM on, Secure Boot off, ≥4 vCPU, 16 GB, 256 GB).
- Azure Bastion and a NAT Gateway (no public IP on the VMs).
- A staging storage account for the Azure-staged ROE ISO and Configurator App.
- A Key Vault for the ownership voucher.
- A Log Analytics workspace, and an optional Windows 11 jumpbox for staging artifacts.

For host SKU options, the nested VM count, and the full cost breakdown, see
[SFF sizing and cost](sizing.md).

## The end-to-end flow

The SFF profile is the first stage of a longer chain that ends with a managed Kubernetes
cluster:

1. **Deploy and build** — the host builds the nested ROE test VM. See
   [SFF quickstart](quickstart.md).
2. **Provision** — download the ownership voucher and provision the machine into Azure. See
   [SFF runbook](runbook.md).
3. **Run Kubernetes** — optionally deploy a single-node AKS on bare metal cluster onto the
   provisioned machine. See [AKS on bare metal](aks-baremetal.md).

For the fully automated path that chains every stage with one orchestrator, see
[Zero-touch deployment](zero-touch.md).

## Provenance

The SFF profile is original work in this repository, plus vendored Microsoft helper scripts
(MIT) and a read-only mirror of the upstream Microsoft SFF documentation (CC BY 4.0). See
[ATTRIBUTION.md](../../ATTRIBUTION.md) and [Vendored SFF docs](../azure-local-sff/README.md).

## Next steps

- Deploy the host and build the test VM: [SFF quickstart](quickstart.md).
- Plan capacity and cost: [SFF sizing and cost](sizing.md).
- See the hands-off path: [Zero-touch deployment](zero-touch.md).

---

[Documentation home](../README.md) · [Choose a profile](../choose-a-profile.md) · [Glossary](../glossary.md)
