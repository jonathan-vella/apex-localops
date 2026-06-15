# Glossary

[Documentation home](README.md) / Glossary

Definitions for the acronyms and terms used across the apex-localops documentation. Terms are
grouped by area. Each guide links here on first use of an unfamiliar term.

## Profiles and components in this repo

| Term | Definition |
| --- | --- |
| **apex-localops** | This repository. It deploys nested Azure Local evaluation environments inside a single Azure virtual machine (VM). |
| **LocalBox profile** | The vendored, Jumpstart-based profile. It builds a nested 2- or 3-node Azure Local cluster plus a management host from prebaked Arc Jumpstart artifacts. See [LocalBox overview](localbox/overview.md). |
| **Self-hosted profile** | The clean-room profile (also called *zero-Jumpstart*). It builds the same nested cluster from operator-staged ISOs, with no prebaked Jumpstart images or modules. See [Self-hosted overview](selfhosted/overview.md). |
| **SFF profile** | The Small Form Factor profile. It builds a single nested edge test VM at roughly one-tenth the cost of the cluster profiles. See [SFF overview](sff/overview.md). |
| **Jumpstart (Arc Jumpstart)** | A Microsoft project of ready-to-deploy sandbox environments. The LocalBox profile is derived from its LocalBox sandbox. |
| **Profile** | One of the three deployment paths above. Each profile has its own quickstart, sizing guide, and Bicep templates. |

## Azure Local and clustering

| Term | Definition |
| --- | --- |
| **Azure Local** | Microsoft's hyperconverged infrastructure operating system (formerly Azure Stack HCI). It runs virtualized and containerized workloads on-premises and connects to Azure through Arc. |
| **Nested virtualization** | Running a hypervisor (Hyper-V) inside a VM that is itself virtualized. Every profile uses it to build an Azure Local environment inside one Azure VM. |
| **Node** | A single server in an Azure Local cluster. The cluster profiles build two or three nested nodes. |
| **Witness** | A tie-breaker that gives an even-node cluster quorum. A **cloud witness** uses an Azure storage account; a **file-share witness** uses an SMB share. A 3-node cluster has odd quorum and needs no witness. |
| **Quorum** | The voting mechanism that keeps a cluster online. An odd number of nodes avoids the need for a witness. |
| **ROE (Maintenance OS)** | The Recovery Operating Environment that an SFF device boots first. The SFF profile drives a nested VM to the "ROE setup completed successfully" state. |
| **WAC (Windows Admin Center)** | A browser-based management console for Windows Server and Azure Local. It runs inside the nested management host. |
| **DC (Domain Controller)** | The nested server that provides Active Directory, DNS, and time (NTP) for the cluster. |

## Storage

| Term | Definition |
| --- | --- |
| **S2D (Storage Spaces Direct)** | The software-defined storage feature that pools the nodes' local disks into shared cluster storage. |
| **Storage pool (`V:`)** | The Windows storage pool created from the host's data disks. The nested VMs' virtual disks live on it. |
| **VHDX** | A Hyper-V virtual hard disk file. The self-hosted profile converts ISOs into bootable VHDX images. |
| **Premium SSD** | An Azure managed-disk tier backed by solid-state storage with provisioned performance. |
| **P15 / P30** | Premium SSD performance tiers. A 256 GB disk bills at the **P15** baseline by default; setting the tier to **P30** keeps the capacity but raises throughput (and cost). |
| **LRS (Locally redundant storage)** | A storage redundancy option that keeps three copies within a single datacenter. |
| **IOPS** | Input/output operations per second — a measure of disk throughput. |

## Networking

| Term | Definition |
| --- | --- |
| **Azure Bastion** | A managed service that provides RDP and SSH access to a VM through the Azure portal, with no public IP on the VM. |
| **NAT Gateway** | A managed service that provides outbound internet connectivity for a subnet that has no public IP. |
| **NSG (Network security group)** | A set of inbound and outbound firewall rules applied to a subnet or network interface. |
| **PIP (Public IP)** | A public IP address. In this repo only the NAT Gateway and Bastion hold one; the VMs do not. |
| **RRAS** | Routing and Remote Access Service — the Windows role that the nested router VM uses to route traffic. |
| **WinNAT** | The Windows host's built-in network address translation, used to bridge nested traffic onto the host's Azure network interface. |
| **Router VM** | The nested VM that acts as the default gateway for the management subnet, mirroring the Jumpstart `vm-router` design. |
| **IMDS (Instance Metadata Service)** | The Azure metadata endpoint at `169.254.169.254`. The SFF profile denies the nested VM access to it. |

## Identity and access

| Term | Definition |
| --- | --- |
| **Microsoft Entra ID** | Microsoft's cloud identity service (formerly Azure Active Directory). |
| **RBAC (Role-based access control)** | The Azure model that grants identities permissions through role assignments. |
| **Managed identity (MI)** | An Entra identity assigned to an Azure resource so it can authenticate without stored secrets. The host and jumpbox VMs use one to read storage. |
| **UAA (User Access Administrator)** | The role that allows creating role assignments. The self-hosted in-VM deploy needs it because it both creates resources and assigns roles. |
| **Resource provider (RP)** | The Azure service that supplies a resource type. Each profile registers the RPs it needs before deploying. |
| **Service principal object ID** | The directory object ID of a resource provider's identity. The LocalBox deploy resolves the Azure Local RP object ID at runtime. |
| **Ownership voucher** | A signed `.pem` document that proves ownership of an SFF device and authorizes provisioning it into Azure. |

## Kubernetes and edge

| Term | Definition |
| --- | --- |
| **AKS (Azure Kubernetes Service)** | Microsoft's managed Kubernetes service. **AKS on bare metal** runs Kubernetes directly on an SFF device with no hypervisor. |
| **Arc (Azure Arc)** | The control plane that projects on-premises servers, clusters, and Kubernetes into Azure for management. |
| **Arc proxy** | A local process started by `connect-aks-baremetal.sh` that tunnels `kubectl` traffic to an Arc-connected cluster. |
| **EdgeMachine** | The Azure resource (`Microsoft.AzureStackHCI/edgeMachines`) that represents a provisioned SFF device. |
| **DevicePool** | The resource that binds an EdgeMachine to the cluster-management platform and triggers creation of a custom location. |
| **Custom location** | An Arc extension target that points Azure deployments at a specific on-premises device or cluster. |
| **DDA (Discrete Device Assignment)** | A Hyper-V feature that passes a physical device, such as a GPU, directly to a guest VM. |
| **Cilium** | The eBPF-based container networking (CNI) plugin used by the AKS on bare metal preview. |
| **ZTP (Zero-touch provisioning)** | The preview feature (`Microsoft.DeviceOnboarding/AzureLocalZTP`) that automates onboarding an SFF device. |

## Cost and licensing

| Term | Definition |
| --- | --- |
| **AHB (Azure Hybrid Benefit)** | A licensing benefit that removes the per-core Windows surcharge from a VM when you hold eligible licenses. It is on by default in every profile. |
| **PAYG (Pay-as-you-go)** | License-included billing, where Windows licensing is added to the compute rate instead of using AHB. |
| **Software Assurance** | A Microsoft licensing program whose active coverage is one way to qualify for AHB. |

## Deployment tooling

| Term | Definition |
| --- | --- |
| **Bicep** | The domain-specific language for authoring Azure Resource Manager (ARM) templates. All infrastructure in this repo is defined in Bicep. |
| **ARM (Azure Resource Manager)** | The Azure deployment and management layer that Bicep compiles to. |
| **what-if** | An Azure deployment preview that reports the changes a template would make before you apply it. |
| **CSE (Custom Script Extension)** | A VM extension that runs a setup script (`Bootstrap.ps1`) after the VM is created. |
| **DSC (Desired State Configuration)** | A PowerShell configuration system used by the in-VM LocalBox build. |
| **Preflight** | The fast local checks `deploy*.sh` runs before a deployment to fail early on misconfiguration. |
| **Progress tag** | A resource-group tag (for example `DeploymentProgress`, `SffProgress`, `ApexProgress`) the in-VM scripts update at each milestone so the monitor scripts can track the build without signing in. |

---

[Documentation home](README.md) · [Choose a profile](choose-a-profile.md)
