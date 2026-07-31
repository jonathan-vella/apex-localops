# apex-localops documentation

Evaluate Azure Local — a full cluster or a Small Form Factor edge device — inside a single
Azure VM, with no physical hardware. This is the documentation hub: start here, pick a
profile, and follow its guide.

> [!NOTE]
> **Draft release — work in progress.** This project is still being built and validated.
> Templates, scripts, and docs may change, and not every profile has been validated end to end.
> See [Project status](../README.md#project-status) for the per-profile maturity.

- New to the project? Read [Choose a profile](choose-a-profile.md) to pick the right path.
- Unfamiliar with a term? See the [Glossary](glossary.md).
- Looking for the code and badges? See the [project README](../README.md).

## Choose a profile

apex-localops ships two evaluation profiles. Each one builds a nested Azure Local
environment inside one Azure VM and deploys into a Bastion-only resource group with no public
IP on the VMs.

| Profile | What it builds | Est. cost (24×7) | Start here |
| --- | --- | --- | --- |
| **Self-hosted** | A nested 3-node Azure Local cluster, built clean-room from operator-staged ISOs (no Arc Jumpstart dependency) | ~$7,850/mo | [Self-hosted quickstart](selfhosted/quickstart.md) |
| **Small Form Factor (SFF)** | A single nested edge test VM (Maintenance OS / ROE) at roughly one-tenth the cost | ~$700–900/mo | [SFF quickstart](sff/quickstart.md) |

For a feature-by-feature comparison and a decision guide, see [Choose a profile](choose-a-profile.md).

> [!NOTE]
> SFF on a VM is a **preview** evaluation path and is for testing only. Production SFF must
> run on [validated hardware](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview#supported-devices).

## Architecture at a glance

The Self-hosted profile builds a nested 3-node cluster with a domain controller and router
inside one Hyper-V host VM, from OS ISOs staged through a jumpbox. SFF uses a lighter
single-host topology. See each profile's overview for its detailed diagram.

```mermaid
flowchart TB
    User(["Operator"])

    subgraph RG["Azure subscription · resource group rg-apexlocal"]
        direction TB

        subgraph Edge["Edge / network — no public IP on the VMs"]
            Bastion["Azure Bastion"]
            NAT["NAT Gateway"]
        end

        KV["Key Vault"]
        LAW["Log Analytics"]
        Jump["ISO-staging jumpbox<br/>(stages the two OS ISOs)"]

        subgraph Host["Self-hosted host · Standard_E64s_v6 · Hyper-V"]
            direction TB
            subgraph Cluster["Nested Azure Local cluster — 3 nodes, no witness"]
                direction LR
                H1["node 1"]
                H2["node 2"]
                H3["node 3"]
            end
            Mgmt["Domain Controller · RRAS/BGP router<br/>(nested VMs built from ISOs)"]
            Pool["8 × 1024 GB P30 disks<br/>Storage Spaces Direct pool"]
        end
    end

    User -->|HTTPS via portal| Bastion
    Bastion --> Host
    Bastion --> Jump
    Cluster -. S2D .-> Pool
```

**Diagram key:** solid arrows are network paths; the dotted arrow is the Storage Spaces Direct
(S2D) data path that pools the host disks. The operator reaches the host only through Azure
Bastion. Per-profile diagrams live in each profile's overview:
[Self-hosted](selfhosted/overview.md) · [SFF](sff/overview.md).

## Cost at a glance

Every profile bills for **disks, Bastion, and NAT Gateway even when the VMs are stopped**.
Delete the resource group to stop all charges. Figures are retail pay-as-you-go in Sweden
Central (self-hosted and the SFF host), with Azure Hybrid Benefit on.

| Profile | Always-on (24×7) | Deallocated floor | Full breakdown |
| --- | --- | --- | --- |
| Self-hosted | ~$7,850/mo | meaningful floor | [Self-hosted sizing](selfhosted/sizing.md) |
| SFF | ~$700–900/mo | ~$250/mo | [SFF sizing](sff/sizing.md) |

## Documentation index

### Self-hosted profile

| Guide | What's inside |
| --- | --- |
| [Overview](selfhosted/overview.md) | The clean-room topology, the RBAC model, and the end-to-end build flow. |
| [Runbook](selfhosted/runbook.md) | The full path in one place: build the cluster, deploy workloads (VMs, SQL, AVD, AKS), verify, and tear down to $0. |
| [Quickstart](selfhosted/quickstart.md) | Register providers, deploy, stage the two ISOs from the jumpbox, monitor the build, and confirm success. |
| [Sizing and cost](selfhosted/sizing.md) | Fixed release topology, regional quota, cost control, and the build time budget. |
| [Troubleshooting](selfhosted/troubleshooting.md) | Evidence collection, supported cluster-only recovery, secret cleanup, and full redeployment boundaries. |
| [Validation](selfhosted/validation.md) | The release gate, the per-run evidence schema, and where release evidence is published. |

### Small Form Factor profile

| Guide | What's inside |
| --- | --- |
| [Overview](sff/overview.md) | The SFF topology, what gets deployed, and how the pieces fit together. |
| [Quickstart](sff/quickstart.md) | Register providers, deploy, stage the ROE ISO and Configurator App, and monitor the build. |
| [Runbook](sff/runbook.md) | Download the ownership voucher and provision the machine from the Azure portal. |
| [Zero-touch deployment](sff/zero-touch.md) | Chain every stage — providers through AKS — with one orchestrator. |
| [AKS on bare metal](sff/aks-baremetal.md) | Deploy a single-node, Arc-connected Kubernetes cluster onto the provisioned machine. |
| [Sizing and cost](sff/sizing.md) | Host SKU options, nested VM count, cost, and the cluster-vs-SFF comparison. |

### Reference

| Guide | What's inside |
| --- | --- |
| [Choose a profile](choose-a-profile.md) | Side-by-side comparison and a decision guide. |
| [Roadmap and known limitations](roadmap.md) | Per-profile maturity, what is being validated, and known limitations. |
| [Glossary](glossary.md) | Acronyms and terms used throughout the docs. |
| [Vendored SFF docs](azure-local-sff/README.md) | How the upstream Microsoft SFF documentation mirror is used. |

## Recommended journeys

Each journey starts at a quickstart and ends with a running environment.

- **Build the full cluster (clean-room):** [Choose a profile](choose-a-profile.md) →
  [Self-hosted overview](selfhosted/overview.md) → [Self-hosted sizing](selfhosted/sizing.md) →
  [Self-hosted quickstart](selfhosted/quickstart.md) → [Troubleshooting](selfhosted/troubleshooting.md) if needed.
- **Evaluate an edge device:** [SFF overview](sff/overview.md) →
  [SFF quickstart](sff/quickstart.md) → [SFF runbook](sff/runbook.md) →
  [AKS on bare metal](sff/aks-baremetal.md). For the hands-off path, use
  [Zero-touch deployment](sff/zero-touch.md).

---

[Project README](../README.md) · [Choose a profile](choose-a-profile.md) · [Glossary](glossary.md)
