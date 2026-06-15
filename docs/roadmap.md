# Roadmap and known limitations

[Documentation home](README.md) / Roadmap

apex-localops is a **draft release** under active development. This page tracks what is
validated today, what is still being hardened, and the known limitations of each profile. It is
a living document — expect it to change as the project matures. For the detailed history, see
the [CHANGELOG](../CHANGELOG.md); for per-profile maturity at a glance, see
[Project status](../README.md#project-status).

## Maturity by profile

| Profile | Maturity | Status |
| --- | --- | --- |
| [LocalBox](localbox/overview.md) | Most mature | Tagged releases exist; pin `githubBranch` to a tag for reproducible deploys. |
| [Self-hosted](selfhosted/overview.md) | Preview | Functional clean-room build; still being validated across regions and Azure Local builds. |
| [SFF](sff/overview.md) | Preview | Evaluation only; flows and artifact names may change. |
| [AKS on bare metal](sff/aks-baremetal.md) | Preview | East US only, single-node, Cilium; depends on preview Azure APIs. |

## Being validated and hardened

These areas work but are still being exercised and may change:

- **End-to-end deployment validation** across more regions and subscription types. CI covers
  Bicep, shell, skills, and docs — not live deployments — so real-world runs are how coverage
  grows.
- **Self-hosted build robustness** across different Azure Local and Windows Server ISO builds
  (the ISO-to-VHDX conversion is the highest-risk step).
- **SFF and AKS preview tracking.** Both ride preview Azure APIs and portal flows; the templates
  pin preview API versions that will need periodic bumps as the previews evolve.
- **Documentation completeness.** The doc set was recently restructured; gaps and rough edges
  are expected — please report them.

## Known limitations

These are intentional or upstream constraints, not bugs:

- **Cost while stopped.** Every profile bills for disks, Bastion, and the NAT Gateway even when
  the VMs are deallocated. Delete the resource group to reach $0. See each profile's sizing
  guide.
- **No public IP on the VMs.** Access is over Azure Bastion only, by design.
- **Azure Hybrid Benefit is on by default.** The cost estimates assume you hold eligible
  licenses. Opt out for license-included billing if you do not — see the sizing guides.
- **SFF is for evaluation only.** Production SFF must run on
  [validated hardware](https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview#supported-devices).
- **AKS on bare metal preview constraints.** East US only, a single control-plane node, Cilium
  CNI, and `NodePort` (not `LoadBalancer`) services.
- **Two manual touchpoints in the SFF chain.** Staging the Microsoft-owned ROE ISO and
  Configurator App (one time), and the portal machine-provisioning step where the preview CLI is
  unavailable. See [Zero-touch deployment](sff/zero-touch.md).
- **Region split for the cluster profiles.** Infrastructure and the Azure Local instance use
  separate regions; not every region supports the instance. See the sizing guides.

## Out of scope

- **Production use.** This project builds evaluation environments, not production systems.
- **Editing vendored mirrors.** `docs/upstream/**`, `docs/azure-local-sff/upstream/**`, and
  `artifacts/sff/vendor/**` are read-only — change upstream and re-sync instead.

## Help shape it

Found a gap, a bug, or a region that does not work? Please
[open an issue](https://github.com/jonathan-vella/apex-localops/issues). Contributions are
welcome — see [CONTRIBUTING.md](../CONTRIBUTING.md).

---

[Documentation home](README.md) · [Choose a profile](choose-a-profile.md) · [Glossary](glossary.md)
