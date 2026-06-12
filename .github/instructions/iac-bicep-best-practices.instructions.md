---
description: "Bicep best practices for the Azure Local infrastructure templates under infra/bicep/: naming, parameters, security defaults, validation."
applyTo: "infra/bicep/**/*.bicep"
---

# Bicep Best Practices

> Adapted from [jonathan-vella/apex](https://github.com/jonathan-vella/apex)
> `.github/instructions/iac-bicep-best-practices.instructions.md`, **heavily** retargeted for
> apex-localops. apex's governance machinery (`AGENTS.md`, `04-governance-constraints.json`,
> `04-iac-contract.json`, AVM-freeze validator, mandatory budget module, `azure-defaults` skill)
> does **not** exist here and has been removed. These templates are nested Azure Local eval
> infrastructure, not a WAF landing zone.

## Scope

Owned templates live under `infra/bicep/` (`azlocal-js`, `azlocal-selfhosted`, `azlocal-sff`,
`aks-baremetal`). Each profile has a `main.bicep` plus `host/`, `network/`, `mgmt/` modules.

## Authoring rules

| Rule | Standard |
| --- | --- |
| Identifiers | lowerCamelCase for params, vars, resources, modules |
| Descriptions | `@description('...')` on every parameter and output |
| Secrets | `@secure()` on passwords/keys; never a default value; resolve at deploy time |
| Unique names | Generate `uniqueString(resourceGroup().id)` once; pass the suffix to modules |
| Length limits | Use `take()` for length-constrained names (Storage 24, Key Vault 24) |
| Dependencies | Prefer symbolic references over explicit `dependsOn` |
| Outputs | Modules output `resourceId` + `resourceName` (and `principalId` when an identity exists) |

## Security defaults

Carry the repo's established posture (see [ATTRIBUTION.md](../../ATTRIBUTION.md) and existing
templates) — no public IPs on VMs (Bastion + NAT), and for any storage/data resources:

```bicep
// Storage
supportsHttpsTrafficOnly: true
minimumTlsVersion: 'TLS1_2'
allowBlobPublicAccess: false
```

Secrets and tenant-specific GUIDs are **resolved at deploy time**, never committed to parameter
files (this is an explicit derivative change from upstream LocalBox).

## Validation (matches CI)

```bash
az bicep build --file infra/bicep/<profile>/main.bicep --stdout > /dev/null
az bicep lint  --file infra/bicep/<profile>/main.bicep
```

[.github/workflows/validate.yml](../workflows/validate.yml) builds + lints `azlocal-js`,
`azlocal-sff`, and `aks-baremetal` and fails on any Error-level diagnostic.

## Anti-patterns

| Anti-pattern | Solution |
| --- | --- |
| Hardcoded globally-unique names | `uniqueString()` suffix, generated once |
| Missing `@description` | Document all parameters and outputs |
| Explicit `dependsOn` | Use symbolic references |
| Committed secrets / tenant GUIDs | `@secure()` params resolved at deploy time |
| Public IP on a VM | Bastion + NAT Gateway (repo default) |
