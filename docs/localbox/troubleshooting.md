# LocalBox troubleshooting

[Documentation home](../README.md) / LocalBox / Troubleshooting

This guide covers failures in the LocalBox profile — the nested Azure Local cluster build — and
how to recover from them. To deploy, see the [LocalBox quickstart](quickstart.md).

> [!NOTE]
> This guide covers the LocalBox cluster profile. For the Small Form Factor profile, see the
> troubleshooting table in the [SFF runbook](../sff/runbook.md) and the vendored upstream guide
> [small-form-factor-troubleshoot.md](../azure-local-sff/upstream/small-form-factor-troubleshoot.md).
> For AKS on bare metal, see [AKS on bare metal](../sff/aks-baremetal.md) and the
> `connect-aks-baremetal.sh` Arc-proxy path.

## In this guide

- [Start here: read the logs](#start-here-read-the-logs)
- [Cluster witness and the shared-key policy](#cluster-witness-and-the-shared-key-policy)
- [Cluster build fails with InvalidResourceLocation](#cluster-build-fails-with-invalidresourcelocation)
- [Preflight blocks the deploy](#preflight-blocks-the-deploy)
- [Quota or capacity errors at deploy time](#quota-or-capacity-errors-at-deploy-time)
- [Password rejected](#password-rejected)
- [Artifacts fail to download inside the VM](#artifacts-fail-to-download-inside-the-vm)
- [Cluster build succeeds but tests fail](#cluster-build-succeeds-but-tests-fail)

## Start here: read the logs

The ARM deployment is the easy part (~18 minutes). Most issues surface during the in-VM cluster
build (2–4 hours), which has no Azure-visible deployment state. Start with the monitor and the
in-VM logs:

```bash
./scripts/monitor.sh --once --logs
```

In-VM logs live at `C:\LocalBox\Logs\` (reachable over Azure Bastion, or remotely with
`az vm run-command`). The master log is `New-LocalBoxCluster.log`.

## Cluster witness and the shared-key policy

This repo defaults to a 3-node cluster specifically so that **no witness is required** (odd
quorum). That avoids the Azure Local cloud witness, which creates a storage account and
authenticates to it with a shared account key. If your tenant enforces a policy that sets
`allowSharedKeyAccess = false` on storage accounts, a cloud witness fails validation with
`Test-AzStackHciClusterWitness` / `UpdateDeploymentSettingsDataFailed` — and you cannot fix it
by toggling the account, because the policy re-applies.

- **Default (3 nodes):** `witnessType = "No Witness"` in `artifacts/azlocal.parameters.json`.
  There is nothing to configure, no witness storage account, and no shared-key dependency.
- **If you switch back to 2 nodes:** a witness becomes mandatory. With a shared-key-deny policy
  in place, a cloud witness will not work; use a file-share witness instead (set `witnessType`
  accordingly and provide `witnessPath`), or exempt the witness storage account from the policy.

## Cluster build fails with InvalidResourceLocation

> [!NOTE]
> This applies only when using a cloud witness (2-node clusters). The default 3-node config has
> no witness storage account and is not affected.

**Symptom** (in `New-LocalBoxCluster.log`, around "Step 10/11"):

```text
Code=InvalidResourceLocation; Message=The resource 'localbox<hash>' already exists in
location 'X' ... cannot be created in location 'Y'.
```

**Cause:** the staging storage account doubles as the Azure Local cluster witness.
`Generate-ARM-Template.ps1` maps it to `ClusterWitnessStorageAccountName`, and the generated
`azlocal.json` creates the witness at `location = azureLocalInstanceLocation`. If the outer
Bicep created that account in a different region, the in-VM cloud deployment aborts. The nested
nodes build and Arc-register first, so the failure surfaces about 90 minutes in.

**Prevention** (already encoded): `infra/bicep/azlocal-js/main.bicep` provisions the staging
account with `location: azureLocalInstanceLocation`, and `deploy.sh` preflight blocks a
mismatched existing account.

**Recovery** without rebuilding the nodes: delete the mislocated (empty) `localbox<hash>`
account, then re-run only the cluster cloud deployment from inside the VM — the Arc-registered
nodes are preserved:

```powershell
# inside LocalBox-Client (over Azure Bastion or az vm run-command)
Connect-AzAccount -Identity
New-AzResourceGroupDeployment -ResourceGroupName <rg> `
  -TemplateFile C:\LocalBox\azlocal.json `
  -TemplateParameterFile C:\LocalBox\azlocal.parameters.json
```

## Preflight blocks the deploy

`deploy.sh` preflight is intentionally strict. Each failure maps to a real, expensive-to-discover
problem:

| Message | Fix |
| --- | --- |
| `main.bicep does not compile` | Run `az bicep build --file infra/bicep/azlocal-js/main.bicep` and fix the error. |
| `spnProviderId did not resolve` | Run `./scripts/check-providers.sh`, or `export LOCALBOX_SPN_PROVIDER_ID=<guid>`. |
| `not registered: <providers>` | Run `./scripts/check-providers.sh` and wait for registration. |
| `staging/witness SA is in 'X' but azureLocalInstanceLocation='Y'` | Delete the mislocated `localbox<hash>` account, then redeploy. |

Bypass with `--skip-preflight` only if you understand the consequence.

## Quota or capacity errors at deploy time

```text
SkuNotAvailable / OperationNotAllowed: ... quota ...
```

You lack `Standard_E64s_v6` capacity in the region. Check and request it:

```bash
az vm list-usage --location swedencentral -o table | grep -iE "ESv6"
```

Either request a quota increase (the 3-node default needs 64 vCPUs), or choose another
infrastructure region with `-l <region>`.

## Password rejected

The Windows admin password must be 14–123 characters with three of lowercase, uppercase, digit,
and special, and **must not contain `$`** (it breaks the in-VM logon script). `deploy.sh`
validates this before deploying.

## Artifacts fail to download inside the VM

The VM fetches `artifacts/` from this repo's raw URLs. If downloads fail:

- Confirm the repo is public and the path resolves, for example:

  ```bash
  curl -sfI https://raw.githubusercontent.com/jonathan-vella/apex-localops/main/artifacts/PowerShell/Bootstrap.ps1
  ```

  This should return `HTTP/2 200`.
- If you pinned `githubBranch` to a tag, confirm the tag exists and contains `artifacts/`.
- Outbound HTTPS egress from the VM goes through the NAT Gateway — confirm it deployed.

## Cluster build succeeds but tests fail

A `DeploymentStatus` like `Tests succeeded: 9 Tests failed: 3` with
`DeploymentProgress = Failed` means the build reached the validation phase but the cluster did
not fully form. Open `New-LocalBoxCluster.log` and search upward from the first `Tests failed`
line for the first hard error (often the witness storage account issue above, or a
provider-registration race). `monitor.sh` tracks the authoritative
`Microsoft.AzureStackHCI/clusters` resource rather than this advisory tag.

## Next steps

- Return to the deployment steps: [LocalBox quickstart](quickstart.md).
- Review sizing constraints: [LocalBox sizing and cost](sizing.md).

---

[Documentation home](../README.md) · [LocalBox overview](overview.md) · [Glossary](../glossary.md)
