# Attribution

This repository is a **derivative work** of the Microsoft **Arc Jumpstart LocalBox**
sandbox and is distributed under the same license, **Creative Commons Attribution 4.0
International (CC BY 4.0)** — see [LICENSE](LICENSE).

## Original work

- **Title:** Arc Jumpstart — LocalBox (`azure_jumpstart_localbox`)
- **Source:** <https://github.com/microsoft/azure_arc>
- **Author / copyright:** © Microsoft Corporation and Arc Jumpstart contributors
- **Vendored from commit:** `027b9554b2534af190271bd7443d8556da745d3e`
- **License:** Creative Commons Attribution 4.0 International (CC BY 4.0) —
  <https://creativecommons.org/licenses/by/4.0/>

## Changes made in this derivative

Per CC BY 4.0 §3(a)(1)(B), the following modifications were made to the original:

- **Self-hosting:** the in-VM `artifacts/` tree is vendored into this repository and the
  Bicep `templateBaseUrl` is repointed at this repo's raw URLs (added a `githubRepo`
  parameter), removing the `microsoft/azure_arc` runtime dependency at deploy time.
- **3-node witnessless cluster:** the nested Azure Local cluster runs **three** nodes
  (`AzLHOST1`/`AzLHOST2`/`AzLHOST3`, `witnessType = "No Witness"`) instead of the upstream
  two-node + cloud-witness design, giving odd quorum with no witness storage account.
- **Host VM size:** the client VM defaults to `Standard_E64s_v6` (64 vCPU / 512 GB) to fit
  the three 96 GB nodes plus the management host.
- **Storage / disks:** the client data disks are pre-created at the **P30** performance
  tier and attached; the count is raised to **12** (3 TB pool) for the 3-node S2D footprint.
- **Management jumpbox:** added an optional **Windows 11** management VM
  (`mgmt/managementVm.bicep`, Trusted Launch) reachable over Azure Bastion.
- **Connectivity defaults:** Bastion + NAT Gateway enabled by default (no public IP on the
  client VM).
- **Region defaults:** Azure infrastructure defaults to `swedencentral`; the Azure Local
  instance registers in `westeurope`.
- **Cluster-witness region fix:** when a cloud witness *is* used, the staging/witness
  storage account is provisioned in the Azure Local instance region to prevent an
  `InvalidResourceLocation` failure during the in-VM cloud deployment.
- **Tooling:** added `scripts/deploy.sh` (preflight + secure password handling + runtime
  identity resolution + monitor hand-off), `scripts/monitor.sh` (observes the in-VM build),
  and `scripts/check-providers.sh`.
- **Identity templatization:** tenant-specific GUIDs and secrets are removed from the
  committed parameters and resolved at deploy time.

## Components under separate Microsoft license terms

The following are downloaded from Microsoft's official sources at build time and are **not**
part of this repository; they remain subject to their own license terms:

- Azure Local / Windows Server **OS VHDX** images.
- **PowerShell 7** and **Windows Admin Center** installers.
- The Arc Jumpstart desktop **wallpaper** image.
- The Azure Local SFF **Maintenance OS (ROE) ISO** and **Configurator App**, which are
  portal/subscription-gated Microsoft artifacts staged at deploy time (never vendored here).

## Small Form Factor (SFF) profile — additional vendored work

The SFF profile ([infra/bicep/azlocal-sff](infra/bicep/azlocal-sff), `artifacts/sff/`,
`scripts/*-sff.sh`) is original work in this repository, plus the following vendored
Microsoft materials:

- **SFF helper scripts** — `artifacts/sff/vendor/set-network.ps1` and
  `artifacts/sff/vendor/setup-k3s-arc.sh` are vendored from
  [`Azure-Samples/AzureLocal`](https://github.com/Azure-Samples/AzureLocal)
  (`small-form-factor/`), pinned to commit
  `963ac3f530ad64cccfd7ab6f13bddda639abee68`. Licensed **MIT** © Microsoft. **Modification:**
  `set-network.ps1` `Get-SubnetMaskFromCidr` was patched for **Windows PowerShell 5.1**
  compatibility (the upstream `[uint32]0xFFFFFFFF` throws under 5.1, the host's default
  shell); the mask is computed via powers of two instead. The patch is marked inline.
- **SFF documentation** — `docs/azure-local-sff/upstream/` is a read-only mirror of the
  `azure-local/small-form-factor` docs from
  [`MicrosoftDocs/azure-stack-docs`](https://github.com/MicrosoftDocs/azure-stack-docs),
  pinned to commit `cb1df90`, refreshed by `.github/workflows/sync-azure-local-sff-docs.yml`.
  Licensed **Creative Commons Attribution 4.0 International (CC BY 4.0)** © Microsoft.

## AKS on bare metal (preview) profile

The AKS on bare metal profile ([infra/bicep/aks-baremetal](infra/bicep/aks-baremetal),
`scripts/*-aks-baremetal.sh`, `docs/aks-baremetal-quickstart.md`) is original work in this
repository. It deploys `Microsoft.Kubernetes/connectedClusters` +
`Microsoft.HybridContainerService/provisionedClusterInstances` (preview API versions) onto an
Arc-enabled SFF machine. The AKS on bare metal preview documentation is **not** vendored here
(it is not yet mirrored to a public GitHub repository); see
<https://learn.microsoft.com/azure/aks/aksarc/aks-bare-metal-overview> for the canonical docs.

## Upstream documentation mirror (Azure Local + Sovereign Cloud)

The [`docs/upstream/`](docs/upstream/) folder is a read-only, **prose-only** mirror of selected
Microsoft documentation, vendored so this repo's hand-authored skills stay grounded in the
latest Microsoft docs and work offline. Only markdown/YAML is mirrored — all media/binaries are
excluded (see [docs/upstream/README.md](docs/upstream/README.md) for the rationale and scope).
Refreshed weekly by `.github/workflows/sync-upstream-docs.yml`.

- **Azure Local, Azure Local max, AKS on Azure Local** — `docs/upstream/azure-local/` (excluding
  `small-form-factor/`), `docs/upstream/azure-local-max/`, and `docs/upstream/aksarc/` are mirrored
  from the `azure-local`, `azure-local-max`, and `AKS-Arc` folders of
  [`MicrosoftDocs/azure-stack-docs`](https://github.com/MicrosoftDocs/azure-stack-docs), pinned to
  commit `cb1df90`. Licensed **Creative Commons Attribution 4.0 International (CC BY 4.0)** ©
  Microsoft. The upstream `LICENSE`, `LICENSE-CODE`, and `ThirdPartyNotices.md` travel with each
  mirrored folder.
- **Microsoft Sovereign Cloud (Azure Local + foundations subset)** —
  `docs/upstream/azure-sovereign-clouds/` is mirrored from the `articles/` folder of
  [`MicrosoftDocs/azure-sovereign-clouds`](https://github.com/MicrosoftDocs/azure-sovereign-clouds),
  pinned to commit `f8b5e52`, limited to the sovereignty foundations, Sovereign Public Cloud
  overviews, and Sovereign Private Cloud content (including Azure Local and Foundry Local);
  Microsoft 365 Local, GitHub Enterprise Local, Dataverse / Power Platform, Dynamics 365 Business
  Central, and National Partner Clouds are excluded. Licensed **Creative Commons Attribution 4.0
  International (CC BY 4.0)** © Microsoft.
