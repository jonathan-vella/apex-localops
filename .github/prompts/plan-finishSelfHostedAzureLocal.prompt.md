## Plan: Finish Self-Hosted Azure Local

Turn the existing self-hosted profile into a release-ready **evaluation** path for one supported 3-node nested topology. The current profile is not only under-tested: it lacks node capacity disks, does not establish the NIC/VLAN contract sent to Azure Local, passes an invalid witness value, uses generic Arc registration instead of the supported Azure Local bootstrap, and does not prepare Active Directory with the required LCM account/OU structure. The recommended path fixes those root causes, locks all runtime dependencies, adds failure-safe secret cleanup and recovery, validates one paid golden deployment from a candidate SHA, then tags that exact SHA as `v1.3.0-rc.1`.

### Phase 1 — Establish the release contract and executable gates

1. **Make self-hosted automation an explicitly owned source root** so repository guidance and review rules apply to it.
   - Update `.github/instructions/instructions.instructions.md`, `.github/instructions/code-quality.instructions.md`, `.github/instructions/powershell.instructions.md`, `.github/instructions/no-heredoc.instructions.md`, and `.github/instructions/no-interactive-shell.instructions.md` to include `artifacts/selfhosted/PowerShell/**` without broadening rules onto vendored LocalBox/SFF trees.
   - Define PowerShell 5.1 compatibility, non-interactive behavior, secure-input handling, and parser/PSScriptAnalyzer/Pester validation for this owned tree.

2. **Add CI coverage before changing behavior**; use tests to encode the supported contract and expose the current failures.
   - Extend `.github/workflows/validate.yml` with self-hosted Bicep build/lint, JSON parsing/contract checks, PowerShell parser + `Test-ModuleManifest`, PSScriptAnalyzer compatibility checks, and Pester tests on `ubuntu-latest`/`pwsh` with pinned tool versions.
   - Add `.github/psscriptanalyzer-settings.psd1` and `artifacts/selfhosted/PowerShell/tests/`.
   - Contract tests must assert: exactly 3 nodes; E64s_v6/12×256-GB-P30/96-GB/16-vCPU fixed geometry; four blank 170-GB S2D VHDXs per node; exact `FABRIC`, `StorageA`, and `StorageB` adapters; spoofing/teaming/trunk configuration; `No Witness`; no witness storage/key secret in the self-hosted ARM template; current LCM password spelling; exact count of three healthy Arc nodes before deployment; deterministic deployment resource names; and unconditional secret cleanup/nonzero failure exit.
   - *Parallel with steps 3–5 once the initial failing baseline is recorded.*

### Phase 2 — Lock and order the Azure infrastructure

3. **Collapse the public Bicep surface to the one validated topology.**
   - In `infra/bicep/azlocal-selfhosted/main.bicep`, `main.bicepparam`, and `host/host.bicep`, remove the reachable 2-node path and unsupported shape toggles. Fix the release geometry to 3 nodes on `Standard_E64s_v6`, 12×256-GB P30 host disks, and 96 GB/16 vCPU per node.
   - Fix Bastion, NAT, management VM, and autologon on for the supported path; remove public-IP and no-jumpbox branches from the release contract.
   - Keep only useful supported inputs: resource group, infrastructure location, cluster name, Azure Hybrid Benefit toggle (default on), tags, and immutable GitHub artifact ref.
   - Restrict infrastructure location to `swedencentral` or `germanywestcentral`; fix Azure Local instance registration to `westeurope`; shorten the default cluster name to 15 characters or fewer for the current template.
   - Set the candidate’s default artifact ref to the reserved `v1.3.0-rc.1`; the golden run will explicitly override it with the candidate commit SHA.

4. **Start CSE automation only after managed-identity RBAC exists.**
   - Split VM creation from `BootstrapApexLocal` and `SetupJumpbox` extension deployment using new `host/bootstrapExtension.bicep` and `mgmt/jumpboxSetup.bicep` modules.
   - In `main.bicep`, deploy VM identities first, assign roles, then deploy extensions with explicit ordering.
   - Keep host MI `Contributor` + `User Access Administrator` at resource-group scope and `Storage Blob Data Contributor` on staging storage; keep jumpbox MI blob contributor. Remove redundant host Reader/Tag Contributor assignments and the deployer blob-owner assignment because the supported upload path uses the jumpbox MI.
   - Replace `utcNow()` force updates with the immutable artifact ref/build version so an unchanged redeploy does not start a second destructive build.

5. **Harden staging storage for the witnessless path.**
   - In `mgmt/stagingStorage.bicep`, set `allowSharedKeyAccess: false`; retain HTTPS/TLS 1.2/no-public-blob and OAuth-only VM access.
   - Keep staging storage in the infrastructure region because the patched 3-node template will no longer declare or key a witness account in West Europe.
   - Add deterministic outputs needed by the bootstrap and golden evidence; do not add private endpoints or cross-profile shared modules in this release.

6. **Make preflight fail before creating billable resources.**
   - Refactor `scripts/deploy-selfhosted.sh` to run Bicep compile/lint, provider state, HCI RP object ID, deployment-role capability, region allow-list, E64s_v6 availability/restrictions, Esv6 quota, fixed topology coherence, pinned marketplace image availability, and required raw artifact URL checks before resource-group creation or password prompting.
   - Treat missing providers/OID/quota/SKU/artifacts as failures, not warnings; remove the supported `--skip-preflight` escape hatch.
    - Add `--artifact-ref`, `--cluster-name`, and `--disable-azure-hybrid-benefit`. Azure Hybrid Benefit entitlement and its default use are pre-authorized for this execution, so the deploy must not pause for confirmation; retain the opt-out only for an explicitly requested PAYG run. Germany West Central is an explicit rerun (`--location germanywestcentral`) after Sweden preflight fails, never an automatic region switch.
   - Update `scripts/check-providers-selfhosted.sh` so its provider set matches the official current Arc/bootstrap/template path and a timeout exits nonzero.

### Phase 3 — Make image and nested-host construction correct and repeatable

7. **Create and verify an ISO manifest.**
   - Update `Setup-Jumpbox.ps1` to fail if its required pinned Az modules or `Upload-Isos.ps1` cannot be staged; keep Azure CLI/AzCopy optional helpers.
   - Update `Upload-Isos.ps1` to require jumpbox managed identity, calculate SHA-256 and byte length, inspect WIM/ESD image metadata, upload both canonical blobs, and publish a structured `iso-manifest.json` only after both uploads verify.
   - Make `Wait-ApexStagedIso` wait for both blobs plus the manifest; make `Get-ApexStagedIso` verify length and SHA-256 after download. Record exact Azure Local and Windows Server image/build metadata without recording secrets.

8. **Make ISO-to-VHDX conversion transactional.**
   - Refactor `Convert-ApexIsoToVhdx` to select and log the expected image explicitly, write a temporary partial VHDX, allocate collision-free mount letters, check DISM and `bcdboot` results, validate EFI/OS/Windows contents, and atomically promote only a valid image.
   - Validate an existing cached base before reuse and delete partial/corrupt files on failure.
   - Remove the currently nonfunctional `-BootFromIso` fallback and all claims that it is supported; this release supports only the DISM path for the exact golden-run ISO pair.

9. **Fail fast on host storage and duplicate orchestration.**
   - In `Bootstrap.ps1`, require all 12 expected Azure data disks and a healthy `V:` pool with sufficient capacity; never continue without `V:`.
   - Align ISO-wait, scheduled-task, and monitor timeouts so the task cannot be killed before the documented build window ends.
   - Use a single-run lock/status file and start one scheduled task only; a same-ref Bicep redeploy must not launch concurrent Phase 2 processes.

10. **Implement the Microsoft virtual-deployment VM geometry.**
    - In `ApexLocal-Config.psd1` and `New-ApexLocalNode`, create each node with a validated 127-GB OS differencing disk plus **four blank dynamic 170-GB capacity VHDXs** on `V:`; attach them uninitialized for S2D and cleanly replace them on a full rebuild.
    - Store VM configuration under the configured `V:` VM path; disable dynamic memory and checkpoints; expose virtualization extensions; use the Windows Secure Boot template and lab vTPM/key protector; disable Hyper-V time synchronization.
    - Create deterministic static MACs for `FABRIC`, `StorageA`, and `StorageB`; enable MAC spoofing and teaming; configure trunk mode with the required native/allowed VLAN range; apply IMDS deny ACLs to every adapter.
    - Map guest NICs by MAC and rename them exactly; configure only `FABRIC` with management IP/gateway/DNS, disable DHCP/DNS registration on storage NICs, and leave storage IP assignment to Network ATC (`enableStorageAutoIp`).
    - Add hard postconditions for disk count/size/CanPool, NIC names/MAC/VLAN settings, Secure Boot/vTPM, and time-source state before Arc onboarding.

11. **Harden router, DC, unattend, and secret lifecycle.**
    - Generate unattend XML through XML APIs so special characters are escaped; remove plaintext answer files from host and every guest immediately after first-boot configuration.
    - Make required RRAS/NAT/DNS/network operations fail on error and verify nested DNS/HTTPS egress.
    - Disable host time integration on the DC, configure it as the authoritative source, and verify node offsets rather than assuming `w32tm` succeeded.
    - Add `Clear-ApexBootstrapSecrets` and call it from `finally` on success and failure: disable/remove Winlogon autologon values, clear `APEX_AdminPasswordB64`, remove answer files and transient token/config files, and zero in-process plaintext variables where practical. Keep the distinct LCM username but reuse the lab admin password per the approved decision.

### Phase 4 — Use the supported Azure Local preparation and deployment path

12. **Prepare Active Directory with Microsoft’s supported tool.**
    - After forest creation, install the pinned `AsHciADArtifactsPreCreationTool` version `10.2402` on the nested DC and call `New-HciAdObjectsPreCreation` over PowerShell Direct.
    - Add a distinct configured LCM username (for example `ApexLocalDeploy`) using the same approved lab password; let the tool create the dedicated OU/sub-OUs, delegated rights, gMSAs, and blocked GPO inheritance.
    - Validate the OU structure, account constraints, interactive/batch-logon prerequisites, naming prefix (≤8), and cluster/node uniqueness. Pass the LCM credential—not domain Administrator—to the cluster ARM deployment.

13. **Run standalone Environment Checker as a release gate.**
    - Add `Test-ApexEnvironmentReadiness` on the outer host using a pinned `AzStackHci.EnvironmentChecker` version and PowerShell Direct sessions to all three nodes.
    - Run connectivity, software/time, AD, network, Arc-integration, and virtual-hardware checks in the documented order. Any unwaived Critical result blocks Arc/deployment; warnings remain evidence. Allow only test-ID-specific virtual-lab deviations demonstrated during the golden run, never a broad hardware bypass.
    - Copy uniquely named raw reports to the private logs container (they contain PII), write only redacted counts/test IDs to the build summary, unload/uninstall the standalone checker from Azure Local nodes before cloud deployment, and rerun affected validators after remediation.

14. **Replace generic Arc registration with official Azure Local initialization.**
    - Refactor `Connect-ApexNodeToArc` to require the current portal ISO’s bundled `Invoke-AzStackHciArcInitialization` and invoke it on each node with the host-MI ARM token, tenant/subscription/RG, `westeurope`, and `AzureCloud`; never fall back to bare `azcmagent connect` or device-code auth.
    - Detect and record the command/module/solution version, avoid logging the token, clear it after each call, and fail unsupported pre-2505 images clearly.
    - Poll until exactly the three expected HybridCompute machines are `Connected`, have identities, and expose the bootstrap/edge state required by the current release. Incomplete discovery is fatal, not a warning.

15. **Refresh and specialize the cluster template for current 2505+ releases.**
    - Replace `artifacts/selfhosted/azlocal.json` from Azure Quickstart Templates commit `b56eb9051390299afe2d913bf2d10861fef279fd` (`quickstarts/microsoft.azurestackhci/create-cluster/azuredeploy.json`) and record its provenance/hash.
    - Apply one documented self-hosted patch: remove/condition all cloud-witness storage, `listKeys`, witness Key Vault secret, deployment-secret entry, and witness dependencies for the fixed `No Witness` topology. This avoids the existing empty-name/region conflict and permits staging storage shared keys to remain disabled.
    - Update `Start-ApexLocalClusterDeployment` to the current `AzureStackLCMAdminPassword` parameter and `2025-09-15-preview` contract; remove old witness arguments; explicitly pass `No Witness`; use deterministic Key Vault/diagnostic names derived from a Bicep-provided suffix so recovery reuses resources.
    - Validate the ARM result object for both `Validate` and `Deploy`; set `ClusterDeploying` before the latter; follow Microsoft’s rule not to rerun Validate after a Deploy-stage failure that could trigger license-sync issues.

16. **Make completion authoritative and failures observable.**
    - Refactor `New-ApexLocalCluster.ps1` into explicit stages with postconditions, milestone timestamps, stage-level log sync, and a durable summary JSON.
    - Make `Connect-ApexAzure` throw after bounded retries. Make the top-level catch tag `Failed`, upload diagnostics, clean secrets, and exit nonzero.
    - Mark `Completed` only after ARM Deploy returns `Succeeded`, the named cluster reports `Succeeded` + `Connected`, all three nodes/required extensions are healthy, host telemetry is present, and the secret-cleanup assertions pass.

### Phase 5 — Operations, documentation, and support boundaries

17. **Complete monitor and recovery tooling.**
    - Update `monitor-selfhosted.sh` to target the configured cluster by name, handle both CLI connectivity field shapes, display stage age/last update, enforce a bounded overall timeout, and treat tags as advisory while cluster state remains authoritative.
    - Add `scripts/recover-selfhosted.sh` for the supported cluster-only recovery point. It prompts for the reused lab password, reconstructs LCM/local credentials transiently, revalidates existing nodes/Arc/AD, and reruns either Validate→Deploy or Deploy-only according to the documented failure stage; it uses a SYSTEM task, uploads logs, and scrubs the supplied secret.
    - Document full cleanup/redeploy for pre-Arc partial builds and use `cleanup-selfhosted.sh` as the only $0-billing teardown. Add a diagnostic collection command/script only if monitor + private log artifacts do not cover the golden-run failure evidence.

18. **Correct all public claims and add an operator runbook.**
    - Rewrite `docs/selfhosted/overview.md`, `quickstart.md`, and `sizing.md` around the fixed 3-node virtual-evaluation contract, four capacity disks/node, official Microsoft AD/Arc/readiness modules, exact primary/fallback region behavior, AHB entitlement, pinned artifacts, transient plaintext/autologon risk, RG-scoped UAA justification, and Microsoft’s statement that virtual deployments are unsupported for production/support.
    - Add `docs/selfhosted/troubleshooting.md` with symptom→evidence→recovery guidance for artifact fetch, ISO integrity/conversion, V:/disk geometry, NIC/Network ATC, AD tool, Environment Checker, Arc initialization, ARM Validate, ARM Deploy, time, role assignment, and cleanup.
    - Add `docs/selfhosted/validation.md` containing the immutable evidence schema/checklist and links to release evidence, but never raw PII reports or secrets.
    - Update `README.md`, `docs/README.md`, `docs/choose-a-profile.md` (currently incorrectly says Self-hosted is Stable), `docs/roadmap.md`, `docs/glossary.md`, `CHANGELOG.md`, `ATTRIBUTION.md`, `SECURITY.md`, `CONTRIBUTING.md`, and `.github/ISSUE_TEMPLATE/bug_report.yml` for ownership, preview/evaluation scope, current template provenance, tested build/ref fields, navigation, cost, and accurate secret handling.
    - Mark `docs/plans/plan-selfHostedAzureLocal.prompt.md` as a superseded design record rather than silently rewriting its historical decisions.
    - Recalculate self-hosted 24×7 and deallocated costs from the Azure Retail Prices API for both infrastructure regions with AHB on, date the estimate, and stop reusing LocalBox’s unverified `$7,850` value.
    - *Documentation drafting can run parallel with phases 3–4; final support/build/cost claims depend on step 21.*

### Phase 6 — Freeze, prove, and release

19. **Freeze a candidate dependency manifest.**
    - Add `artifacts/selfhosted/PowerShell/ModuleVersions.psd1` (or equivalent structured lock) for Az modules, `AsHciADArtifactsPreCreationTool 10.2402`, Environment Checker, Az.StackHCI, CI Pester/PSScriptAnalyzer, and jumpbox-required modules.
    - Resolve and pin one Windows Server 2025 marketplace image version available in both Sweden Central and Germany West Central; retain hashes/build metadata for both operator ISOs; record the bundled Arc initialization version and the pinned Quickstart template commit/hash.
    - Commit all code/tests/docs with default artifact ref `v1.3.0-rc.1`; record this commit as the candidate SHA. Do not create the tag yet.

20. **Pass all static and mocked gates on the candidate SHA.**
    - Run Bicep build/lint, shell syntax/ShellCheck, JSON contract checks, PowerShell parser/manifest/PSScriptAnalyzer/Pester, markdownlint, relative-link checks, secret scanning, and `git diff --check`.
    - Run `az deployment group what-if` with the candidate SHA artifact override; validate Sweden Central and, where subscription capacity permits, a separate no-deploy what-if/preflight for Germany West Central.

21. **Run one clean paid golden deployment from the candidate SHA.**
    - The deployment spend and half-day execution window are pre-authorized. Once the technical gates in steps 19–20 pass, begin the golden run without requesting separate budget, cost, schedule, or duration approval.
    - Try `swedencentral` first. If its preflight blocks on SKU/quota, stop before RG creation and explicitly rerun in `germanywestcentral`; the evidence names whichever infrastructure region actually ran. Always register the instance in `westeurope`.
    - Stage the current portal-recommended Azure Local ISO and Windows Server 2025 ISO through the jumpbox, then capture: manifest hashes/builds; VM image/module/template versions; Bicep outputs/RBAC; private-network posture; V: capacity; all nested VM disk/NIC/security/time postconditions; official AD tool result; Environment Checker summaries; three Arc-connected nodes; Validate and Deploy results; cluster/node/extension health; Azure Monitor telemetry; private build logs; and secret-cleanup assertions.
    - Treat any code/config fix as a new candidate SHA and restart from a clean RG. The successful run must use one unchanged candidate SHA end to end.
    - After evidence is secured, run `cleanup-selfhosted.sh` and verify the RG is gone to stop billing.

22. **Tag and publish the exact successful candidate.**
    - Create annotated tag and GitHub prerelease `v1.3.0-rc.1` on the exact golden-tested SHA; include redacted results, exact ISO/build hashes, region pair, module/template/image versions, known virtual-lab warnings, and private evidence retention location in release notes.
    - Verify raw artifact URLs at the tag and run a post-tag what-if/static smoke check with the default ref (no SHA override).
    - Make a follow-up `main` documentation-only commit that links `docs/selfhosted/validation.md`, roadmap, and changelog to the GitHub release evidence; do not move the tag.

**Relevant files**
- `/workspaces/apex-localops/infra/bicep/azlocal-selfhosted/main.bicep` and `main.bicepparam` — fixed release contract, deterministic names, region/ref/image pins, RBAC ordering.
- `/workspaces/apex-localops/infra/bicep/azlocal-selfhosted/host/host.bicep` plus new `host/bootstrapExtension.bicep` — host VM first, bootstrap after RBAC.
- `/workspaces/apex-localops/infra/bicep/azlocal-selfhosted/mgmt/mgmtVm.bicep`, new `mgmt/jumpboxSetup.bicep`, and `mgmt/stagingStorage.bicep` — reliable jumpbox setup and OAuth-only staging.
- `/workspaces/apex-localops/artifacts/selfhosted/PowerShell/ApexLocalOps/ApexLocalOps.psm1` and `.psd1` — image, fabric, AD, readiness, Arc, deployment, validation, logging, and secret-cleanup ownership.
- `/workspaces/apex-localops/artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1` — the single fixed nested topology and LCM/AD/network/storage names.
- `/workspaces/apex-localops/artifacts/selfhosted/PowerShell/Bootstrap.ps1`, `New-ApexLocalCluster.ps1`, `Setup-Jumpbox.ps1`, and `Upload-Isos.ps1` — ordered bootstrap, state machine, staging, and manifest verification.
- `/workspaces/apex-localops/artifacts/selfhosted/azlocal.json` — current pinned 2505+ create-cluster template with the documented 3-node witnessless patch.
- `/workspaces/apex-localops/artifacts/selfhosted/PowerShell/tests/**` and `ModuleVersions.psd1` — executable contracts and dependency lock.
- `/workspaces/apex-localops/scripts/deploy-selfhosted.sh`, `monitor-selfhosted.sh`, `check-providers-selfhosted.sh`, `cleanup-selfhosted.sh`, and new `recover-selfhosted.sh` — supported operator lifecycle.
- `/workspaces/apex-localops/.github/workflows/validate.yml` and `.github/instructions/*.instructions.md` — CI and owned-source governance.
- `/workspaces/apex-localops/docs/selfhosted/**`, `/workspaces/apex-localops/README.md`, `/workspaces/apex-localops/docs/README.md`, `/workspaces/apex-localops/docs/choose-a-profile.md`, `/workspaces/apex-localops/docs/roadmap.md`, `/workspaces/apex-localops/docs/glossary.md`, `/workspaces/apex-localops/CHANGELOG.md`, `/workspaces/apex-localops/ATTRIBUTION.md`, `/workspaces/apex-localops/SECURITY.md`, `/workspaces/apex-localops/CONTRIBUTING.md`, and the bug template — accurate release/support/security/provenance surface.

**Verification**
1. CI/static: `az bicep build` and `az bicep lint` on `azlocal-selfhosted`; `bash -n` + ShellCheck on all self-hosted scripts; `jq empty`/contract test on the ARM JSON; PowerShell parser, `Test-ModuleManifest`, PSScriptAnalyzer 5.1 compatibility, and Pester; markdownlint + relative-link check; secret scan and `git diff --check`.
2. Behavioral/mocked: prove transactional VHD conversion, four blank capacity disks/node, deterministic NIC/MAC mapping, spoofing/teaming/trunk/IMDS rules, valid escaped unattend XML, official AD/Arc command invocation, exact-three Arc gating, witnessless current ARM contract, deterministic recovery names, cleanup in every exit path, and nonzero failures.
3. Azure no-deploy: artifact-ref reachability, SKU/image/quota/provider/permission preflight, Bicep what-if, no public VM IP, fixed Bastion/NAT, OAuth-only storage, and role scopes.
4. Golden live: one unchanged SHA reaches three Arc-connected nodes and a named Azure Local cluster with `provisioningState=Succeeded` and connectivity `Connected`; all readiness/postdeploy checks pass or have explicit virtual-lab warning IDs; logs/telemetry/evidence exist; bootstrap secrets are absent; monitor exits 0; cleanup removes the RG.
5. Release integrity: `v1.3.0-rc.1` points to the golden SHA, tagged raw URLs resolve, default-ref what-if succeeds, and release notes contain exact build/version/region evidence without PII or secrets.

**Decisions**
- Completion target: release-ready **evaluation**, not production; Microsoft explicitly does not support virtual Azure Local deployments.
- Supported topology: exactly one 3-node, witnessless nested cluster; no 2-node compatibility in this release.
- Supported regions: Sweden Central infrastructure first; explicit Germany West Central infrastructure fallback; Azure Local instance always West Europe. Only the region used by the one golden run is claimed as live-validated; the other remains a statically/preflight-validated fallback.
- Security: retain lab autologon and RG-scoped host MI Contributor + UAA, but scrub transient secret copies, keep VMs Bastion-only, use managed identity/OAuth, and document the exposure honestly.
- LCM identity: a distinct AD account created by Microsoft’s tool, reusing the lab admin password as approved.
- Dependencies: zero Jumpstart means no prebaked Jumpstart VHDs, `Azure.Arc.Jumpstart.*` modules, or vendored Jumpstart scripts; supported Microsoft Azure Local AD/Arc/readiness modules are allowed and pinned.
- Artifact model: golden deployment uses an immutable candidate SHA; success tags that exact SHA as `v1.3.0-rc.1`, which is already the candidate’s default artifact ref.
- Execution authorization: Azure Hybrid Benefit entitlement/default use, the paid Azure deployment, and the half-day golden-run window are pre-authorized; none is an approval checkpoint. Technical readiness checks still gate execution.
- Licensing: Azure Hybrid Benefit remains on by default; users can explicitly disable it for PAYG, and docs must state entitlement requirements without asking for approval during this execution.
- Scope boundary: no LocalBox/SFF shared-module extraction, no production hardening/private endpoint redesign, no multi-region live matrix, no 2-node witness path, and no untested ISO boot fallback.
