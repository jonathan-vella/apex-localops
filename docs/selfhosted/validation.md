# Self-hosted validation and evidence

[Documentation home](../README.md) / Self-hosted / Validation

This page defines the **release gate** for the self-hosted profile and the **evidence schema**
each qualifying deployment must produce. It is the checklist a maintainer follows before tagging
a release and the contract a reviewer uses to confirm a run actually happened. It links to the
published release evidence but never contains raw reports, personally identifiable information
(PII), or secrets.

> [!NOTE]
> The self-hosted profile is in **preview**. See [Project status](../../README.md#project-status)
> and the [roadmap](../roadmap.md). Validation currently covers one subscription and one
> infrastructure region; cross-subscription and cross-tenant portability are **unproven**.

## In this guide

- [Release gate](#release-gate)
- [What is never recorded](#what-is-never-recorded)
- [Per-run evidence schema](#per-run-evidence-schema)
- [Evidence artifacts](#evidence-artifacts)
- [Redacted versus private](#redacted-versus-private)
- [Verification rungs](#verification-rungs)
- [Release evidence](#release-evidence)
- [Next steps](#next-steps)

## Release gate

A single successful deployment does not qualify a release. The gate is **repeatability**:

- **At least two consecutive, fully unassisted deployments** on one unchanged immutable artifact
  ref, each from a clean resource group.
- **No manual in-VM steps** — no Bastion session, no RDP, no hand-uploaded ISO. Staging runs
  through the automated path in the [quickstart](quickstart.md#3-stage-the-two-isos).
- Sweden Central is tried first. If preflight blocks on SKU or quota, the run stops before
  resource-group creation and is rerun explicitly in Germany West Central. Evidence names
  whichever infrastructure region actually ran. The Azure Local instance is always registered in
  Canada Central.
- After evidence is secured for each run, [`cleanup-selfhosted.sh`](../../scripts/cleanup-selfhosted.sh)
  removes the resource group and the teardown is verified.

An independent operator in a different subscription and tenant is **out of scope** for this
release. The release notes must state that gap rather than imply broader validation.

## What is never recorded

Evidence is redacted before it leaves the private log store. The following must **never** appear
in an issue, a commit, this repository, or a release note:

- Lab or LCM passwords, access tokens, storage keys, or any answer file (`unattend.xml`).
- Raw Environment Checker reports (`AzStackHciEnvironmentReport.json` and the per-validator
  copies). They contain machine names, IPs, and account identifiers.
- Any unredacted customer or tenant identifier.

The build scrubs autologon values and transient secret copies on every exit path via
`Clear-ApexBootstrapSecrets`; the evidence for that scrub is an **assertion of absence**, not a
copy of the material.

## Per-run evidence schema

Each qualifying run captures the following. "Redacted" values are safe to publish; "private"
values stay in the logs container and are referenced by name only.

| Evidence | Source | Class |
| --- | --- | --- |
| ISO SHA-256, byte length, image build | `iso-manifest.json` (see [below](#evidence-artifacts)) | Redacted |
| Windows Server / Azure Local image versions | `iso-manifest.json` `files[].images[].version` | Redacted |
| Pinned module / template / marketplace image versions | [ModuleVersions.psd1](../../artifacts/selfhosted/PowerShell/ModuleVersions.psd1) | Redacted |
| Bicep outputs and role assignments | `az deployment group show`, `az role assignment list` | Redacted |
| Private-network posture (no public VM IP, Bastion-only, NAT, OAuth-only storage) | Deployment outputs and resource config | Redacted |
| `V:` pool capacity | Host bootstrap log | Redacted |
| Nested VM disk / NIC / Secure Boot / time postconditions | `New-ApexLocalNode` postcondition log lines | Redacted |
| Official AD tool result | `New-HciAdObjectsPreCreation` output | Redacted |
| Environment Checker summaries (counts and waived test IDs) | `validation-summary-*.json` | Redacted |
| In-guest smoke gate result (per-check status and duration) | `guest-smoke-summary.json` | Redacted |
| Three Arc-connected nodes | `az connectedmachine list` (expect exactly 3 `Connected`) | Redacted |
| ARM Validate and Deploy results | Deployment result objects | Redacted |
| Cluster / node / extension health | `az stack-hci cluster list` (`Succeeded` + `Connected`) | Redacted |
| Azure Monitor telemetry present | Log Analytics workspace | Redacted |
| Secret-cleanup assertions | `Clear-ApexBootstrapSecrets` postconditions | Redacted |
| Raw Environment Checker reports | `AzStackHciEnvironmentReport.json` and per-validator copies | Private |
| Full in-VM build logs | Staging storage `logs/` container | Private |

## Evidence artifacts

Two structured artifacts anchor the schema. Both are produced by the build itself.

`iso-manifest.json` is published by [Upload-Isos.ps1](../../artifacts/selfhosted/PowerShell/Upload-Isos.ps1)
only after both ISO uploads verify by length:

```json
{
  "schemaVersion": 1,
  "generatedUtc": "2026-01-01T00:00:00.0000000Z",
  "files": [
    {
      "label": "Azure Local OS",
      "blob": "AzureLocalOS.iso",
      "bytes": 0,
      "sha256": "<lowercase-hex>",
      "images": [
        { "imageIndex": 1, "imageName": "", "version": "", "architecture": "" }
      ]
    }
  ]
}
```

`validation-summary-ArcIntegration.json` and `validation-summary-HostChecks.json` carry only the
redacted Environment Checker outcome — counts and test IDs, never the raw findings:

```json
[
  {
    "Validator": "Connectivity",
    "CriticalCount": 0,
    "BlockedCount": 0,
    "CriticalTestIds": []
  }
]
```

`CriticalCount` counts findings the checker rated critical; `BlockedCount` counts those **not** on
the waived list in
[ApexLocal-Config.psd1](../../artifacts/selfhosted/PowerShell/ApexLocal-Config.psd1). A run
qualifies only when every validator reports `BlockedCount = 0`. The four waived virtual-lab test
IDs are listed in the [quickstart](quickstart.md#what-this-lab-does-not-validate); any critical
finding outside that exact list blocks the build.

## Redacted versus private

Evidence lives in two tiers:

- **Redacted** — counts, versions, hashes, resource states, and waived test IDs. These are safe to
  publish in the release notes and to link from this page.
- **Private** — raw checker reports and full build logs. These stay in the staging storage `logs/`
  container. The release notes state their retention location; they are never attached to the
  public release.

Confirming a run without exposing private data uses the authoritative control-plane state, not the
progress tag:

```bash
az stack-hci cluster list -g rg-apexlocal \
  --query "[0].{provisioning:provisioningState,connectivity:status}" -o table
az connectedmachine list -g rg-apexlocal \
  --query "[].{name:name,status:status}" -o table
```

The resource-group `ApexProgress` / `ApexStatus` tags are advisory. The cluster resource reaching
`provisioningState=Succeeded` and a connected `status` (`Connected` or the healthy
`ConnectedRecently`), with three `Connected` Arc machines, is the proof.

## Verification rungs

The release is gated by layered checks. Each rung catches a distinct class of defect; passing a
lower rung never substitutes for a higher one.

1. **Static / CI** — `az bicep build`/`lint`, `bash -n` + ShellCheck, JSON contract checks,
   PowerShell parser, `Test-ModuleManifest`, PSScriptAnalyzer 5.1 compatibility, Pester,
   markdownlint, and the relative-link check. Run by
   [validate.yml](../../.github/workflows/validate.yml).
2. **Source contracts** — static assertions that release-critical strings and orderings exist
   (four capacity disks per node, deterministic NIC/MAC mapping, official AD/Arc invocation,
   exact-three Arc gating, witnessless ARM contract, cleanup on every exit path). These match
   source text; they never execute it.
3. **Behavioral unit tests** — executed pure helpers with real inputs (drive-letter selection
   against occupied letters, progress-tag truncation at 256 characters, ISO metadata
   serialization, credential-return shapes).
4. **In-guest smoke** — executed on one throwaway nested VM by
   [Invoke-ApexGuestSmoke.ps1](../../artifacts/selfhosted/PowerShell/Invoke-ApexGuestSmoke.ps1)
   on the cluster host. Its four checks — `GuestProvisioned`, `SecureBootBoot`, `ModuleSideLoad`,
   and `AdPromotionReady` — cover unlettered-partition drive-letter allocation, `unattend.xml`
   injection and verification, Windows Secure Boot template boot, PowerShell Direct readiness,
   side-loaded module import, and post-promotion AD/ADWS readiness. Any failed check exits
   non-zero and blocks promotion to a paid full run.
5. **Azure no-deploy** — resolution of every pin (ISO aliases, marketplace image, module
   versions, artifact URLs), SKU/quota/provider/permission preflight, Bicep what-if, no public
   VM IP, fixed Bastion/NAT, OAuth-only storage, and role scopes.
6. **Repeatability live** — the [release gate](#release-gate) above.
7. **Release integrity** — the published tag points to the proven commit, tagged raw artifact
   URLs resolve, a default-ref what-if succeeds with no SHA override, and the release notes
   contain exact build/version/region evidence without PII or secrets.

## Release evidence

Published evidence is attached to the GitHub release for the qualifying tag:
[apex-localops releases](https://github.com/jonathan-vella/apex-localops/releases). Each release
records the redacted per-run schema above, the exact ISO/build hashes, the region pair, the
module/template/image versions, the known virtual-lab warning IDs, and the private-evidence
retention location.

> [!NOTE]
> The `v1.3.0-rc.1` release does not exist yet. Until the two repeatability runs are captured and
> the tag is published, deploy with an immutable candidate commit SHA as described in the
> [quickstart](quickstart.md#2-deploy-the-infrastructure).

## Next steps

- Deploy and capture evidence: [Self-hosted quickstart](quickstart.md).
- Diagnose a failed run: [Self-hosted troubleshooting](troubleshooting.md).
- Review the topology and RBAC model: [Self-hosted overview](overview.md).

---

[Documentation home](../README.md) · [Self-hosted overview](overview.md) · [Glossary](../glossary.md)
