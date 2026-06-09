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
- **Storage / disks:** the eight client data disks are pre-created at the **P30**
  performance tier and attached.
- **Management jumpbox:** added an optional **Windows 11** management VM
  (`mgmt/managementVm.bicep`, Trusted Launch) reachable over Azure Bastion.
- **Connectivity defaults:** Bastion + NAT Gateway enabled by default (no public IP on the
  client VM).
- **Region defaults:** Azure infrastructure defaults to `swedencentral`; the Azure Local
  instance registers in `westeurope`.
- **Cluster-witness region fix:** the staging/witness storage account is provisioned in the
  Azure Local instance region to prevent an `InvalidResourceLocation` failure during the
  in-VM cloud deployment.
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
