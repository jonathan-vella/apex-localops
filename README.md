<div align="center">

# apex-localops

**Evaluate Azure Local — full cluster or Small Form Factor — inside a single Azure VM. No physical hardware.**

A self-contained, deploy-ready packaging of the Arc Jumpstart **LocalBox** sandbox.

[![validate](https://github.com/jonathan-vella/apex-localops/actions/workflows/validate.yml/badge.svg)](https://github.com/jonathan-vella/apex-localops/actions/workflows/validate.yml)
[![Status: Draft](https://img.shields.io/badge/status-draft%20release-orange)](#project-status)
[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey)](LICENSE)
[![IaC: Bicep](https://img.shields.io/badge/IaC-Bicep-1BA1E2)](infra/bicep/azlocal-js/main.bicep)
![Azure Local](https://img.shields.io/badge/Azure-Local-0078D4)
![Automation: PowerShell](https://img.shields.io/badge/Automation-PowerShell-5391FE?logo=powershell&logoColor=white)

[**Documentation**](docs/README.md) &nbsp;·&nbsp; [**Choose a profile**](docs/choose-a-profile.md) &nbsp;·&nbsp; [**Glossary**](docs/glossary.md)

</div>

> [!IMPORTANT]
> **Draft release — work in progress.** apex-localops is still being built and validated.
> Infrastructure templates, scripts, parameters, and documentation may change without notice,
> and not every profile has been validated end to end. The **LocalBox** profile is the most
> mature; the **Self-hosted**, **SFF**, and **AKS on bare metal** profiles are **preview** and
> still evolving. Use it for evaluation only, and please
> [open an issue](https://github.com/jonathan-vella/apex-localops/issues) if something does not
> work as documented. See [Project status](#project-status) for details.

## Overview

apex-localops stands up complete, nested **Azure Local** (formerly Azure Stack HCI) evaluation
environments inside a **single Azure VM** — no physical hardware. The Bicep templates and the
in-VM build automation are **vendored in this repo**, so a deploy does not depend on any
third-party repository.

## Choose a profile

Three evaluation profiles are included — pick the one you need and follow its guide. For a
feature-by-feature comparison and a decision guide, see
[Choose a profile](docs/choose-a-profile.md).

| Profile | What it builds | Est. cost (24×7) | Get started |
| --- | --- | --- | --- |
| **LocalBox** | A nested 2- or 3-node Azure Local cluster plus a management host (domain controller, router, Windows Admin Center) in one Hyper-V VM | ~$7,850/mo | [LocalBox overview →](docs/localbox/overview.md) |
| **Self-hosted (zero Jumpstart)** | The same nested cluster built clean-room from two operator-staged ISOs — no prebaked Jumpstart VHDs, no `Azure.Arc.Jumpstart.*` modules | ~$7,850/mo | [Self-hosted overview →](docs/selfhosted/overview.md) |
| **Small Form Factor (SFF)** | A lighter single host that builds the SFF Maintenance OS (ROE) test VM — the edge analogue at roughly 1/10th the cost | ~$700–900/mo | [SFF overview →](docs/sff/overview.md) |

> [!NOTE]
> All profiles deploy into a **Bastion-only** resource group (no public IP on the VMs) and
> register the required resource providers via a bundled `check-providers` script. SFF is in
> **preview** and is for testing and evaluation only — production SFF must run on validated
> hardware.

Once an SFF machine is provisioned, you can deploy a managed, Arc-connected
**[AKS on bare metal](docs/sff/aks-baremetal.md)** cluster directly onto it, and the whole SFF
→ voucher → provisioning → AKS → `kubectl` chain can run from a single orchestrator — see
**[zero-touch deployment](docs/sff/zero-touch.md)** (`./scripts/deploy-all.sh`).

## At a glance

Each profile builds its environment as nested VMs inside one Azure host VM, reached only over
Azure Bastion. The architecture diagrams live in the
[documentation hub](docs/README.md#architecture-at-a-glance) and the per-profile overviews.

| Profile | Host VM | Nested payload |
| --- | --- | --- |
| LocalBox | `Standard_E64s_v6` + 12 × 256 GB P30 disks | 3-node cluster (`AzLHOST1/2/3`) + `AzLMGMT` (DC, router, WAC) |
| Self-hosted | `Standard_E64s_v6` + 12 × 256 GB P30 disks, plus an ISO-staging jumpbox | Router VM + domain controller + 3-node cluster, built from ISOs |
| SFF | `Standard_D8s_v5` | One Gen2 ROE test VM (TPM on, Secure Boot off, ≥4 vCPU) |

## Cost

Every profile bills for **disks, Bastion, and NAT Gateway even when the VMs are stopped** —
delete the resource group to stop all charges. Azure Hybrid Benefit is on by default, so the
estimates exclude the Windows licensing surcharge (eligible licenses required).

| Profile | Est. 24×7 | Full breakdown |
| --- | --- | --- |
| LocalBox | ~$7,850/mo (Sweden Central) | [LocalBox sizing and cost](docs/localbox/sizing.md) |
| Self-hosted | ~$7,850/mo (Sweden Central) | [Self-hosted sizing and cost](docs/selfhosted/sizing.md) |
| SFF | ~$700–900/mo (East US) | [SFF sizing and cost](docs/sff/sizing.md) |

## Documentation

Start at the **[documentation hub](docs/README.md)** for the full index and recommended
journeys. Quick links:

- **Choose a profile:** [comparison and decision guide](docs/choose-a-profile.md)
- **LocalBox:** [overview](docs/localbox/overview.md) · [quickstart](docs/localbox/quickstart.md) · [sizing](docs/localbox/sizing.md) · [troubleshooting](docs/localbox/troubleshooting.md)
- **Self-hosted:** [overview](docs/selfhosted/overview.md) · [quickstart](docs/selfhosted/quickstart.md) · [sizing](docs/selfhosted/sizing.md)
- **SFF:** [overview](docs/sff/overview.md) · [quickstart](docs/sff/quickstart.md) · [runbook](docs/sff/runbook.md) · [zero-touch](docs/sff/zero-touch.md) · [AKS on bare metal](docs/sff/aks-baremetal.md) · [sizing](docs/sff/sizing.md)
- **Reference:** [glossary](docs/glossary.md)

## Project status

This is a **draft release** under active development. The table below reflects the current
maturity of each profile; see the [roadmap and known limitations](docs/roadmap.md) for what is
being validated, and the [CHANGELOG](CHANGELOG.md) for the detailed history.

| Profile | Maturity | Notes |
| --- | --- | --- |
| **LocalBox** | Most mature | The original profile; tagged releases exist. Pin `githubBranch` to a tag for reproducible deploys. |
| **Self-hosted** | Preview | Clean-room build; functional but still being validated across regions and Azure Local builds. |
| **SFF** | Preview | For evaluation only — production SFF must run on validated hardware. Flows and artifact names may change. |
| **AKS on bare metal** | Preview | East US only, single-node, Cilium. Depends on preview Azure APIs that may change. |

What this means for you:

- **Expect change.** Template parameters, script flags, resource names, and docs may change
  between commits. Pin to a release tag where a profile supports it.
- **Validation is ongoing.** Not every profile has been run end to end in every region. The
  `validate` workflow covers Bicep, shell, skills, and docs — not live deployments.
- **Feedback welcome.** Please [open an issue](https://github.com/jonathan-vella/apex-localops/issues)
  for bugs, gaps, or doc fixes.

## Contributing and security

- **Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up, validate changes
  locally, and the vendoring boundary (do not edit `docs/upstream/**` or vendored trees).
- **Security:** report vulnerabilities privately — see [SECURITY.md](SECURITY.md). Do not open a
  public issue for security problems.

## Provenance and license

This project packages and customizes the **Arc Jumpstart LocalBox** sandbox from
[`microsoft/azure_arc`](https://github.com/microsoft/azure_arc) (`azure_jumpstart_localbox`),
vendored from commit `027b9554b2534af190271bd7443d8556da745d3e`. As a derivative work it is
distributed under the **same license as upstream — Creative Commons Attribution 4.0
International (CC BY 4.0)**; see [LICENSE](LICENSE) and the credit and list of changes in
[ATTRIBUTION.md](ATTRIBUTION.md). Azure Local OS images, PowerShell, and Windows Admin Center
are downloaded from Microsoft at build time and remain subject to their own license terms.
