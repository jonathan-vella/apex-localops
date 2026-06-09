# Troubleshooting

The ARM deployment is the easy part (~18 min). Most issues surface during the **in-VM
cluster build** (2–4 hours), which has no Azure-visible deployment state. Start with the
monitor and the in-VM logs:

```bash
./scripts/monitor.sh --once --logs
```

In-VM logs live at `C:\LocalBox\Logs\` (reachable via Bastion, or remotely with
`az vm run-command`). The master log is `New-LocalBoxCluster.log`.

## Cluster witness and the `allowSharedKeyAccess` policy

This repo defaults to a **3-node** cluster specifically so that **no witness is required**
(odd quorum). That avoids the Azure Local **cloud witness**, which creates a storage
account and authenticates to it with a **shared (account) key**. If your tenant enforces a
policy that sets `allowSharedKeyAccess = false` on storage accounts, a cloud witness will
fail validation with `Test-AzStackHciClusterWitness` / `UpdateDeploymentSettingsDataFailed`
— and you cannot fix it by toggling the account, because the policy re-applies.

- **Default (3 nodes):** `witnessType = "No Witness"` in `artifacts/azlocal.parameters.json`
  — nothing to configure, no witness storage account, no shared-key dependency.
- **If you switch back to 2 nodes:** a witness becomes mandatory. With a shared-key-deny
  policy in place, a cloud witness will not work; use a **file-share witness** instead
  (set `witnessType` accordingly and provide `witnessPath`), or exempt the witness storage
  account from the policy.

## Cluster build fails: `InvalidResourceLocation` on the `localbox<hash>` storage account

> Applies only when using a **cloud witness** (2-node clusters). The default 3-node config
> has no witness storage account and is not affected.

**Symptom** (in `New-LocalBoxCluster.log`, around "Step 10/11"):

```text
Code=InvalidResourceLocation; Message=The resource 'localbox<hash>' already exists in
location 'X' ... cannot be created in location 'Y'.
```

**Cause:** the staging storage account **doubles as the Azure Local cluster witness**.
`Generate-ARM-Template.ps1` maps it to `ClusterWitnessStorageAccountName`, and the generated
`azlocal.json` creates the witness at `location = azureLocalInstanceLocation`. If the outer
Bicep created that account in a **different** region, the in-VM cloud deployment aborts. The
nested nodes build and Arc-register first, so the failure surfaces ~90 minutes in.

**Prevention (already encoded):** `bicep/main.bicep` provisions the staging account with
`location: azureLocalInstanceLocation`, and `deploy.sh` preflight blocks a mismatched
existing account.

**Recovery** without rebuilding the nodes: delete the mislocated (empty) `localbox<hash>`
account, then re-run only the cluster cloud deployment from inside the VM — the
Arc-registered nodes are preserved:

```powershell
# inside LocalBox-Client (via Bastion or az vm run-command)
Connect-AzAccount -Identity
New-AzResourceGroupDeployment -ResourceGroupName <rg> `
  -TemplateFile C:\LocalBox\azlocal.json `
  -TemplateParameterFile C:\LocalBox\azlocal.parameters.json
```

## Preflight blocks the deploy

`deploy.sh` preflight is intentionally strict. Each failure maps to a real, expensive-to-
discover problem:

| Message                                                           | Fix                                                                              |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `main.bicep does not compile`                                     | Run `az bicep build --file bicep/main.bicep` and fix the error.                  |
| `spnProviderId did not resolve`                                   | Run `./scripts/check-providers.sh`, or `export LOCALBOX_SPN_PROVIDER_ID=<guid>`. |
| `not registered: <providers>`                                     | Run `./scripts/check-providers.sh` and wait for registration.                    |
| `staging/witness SA is in 'X' but azureLocalInstanceLocation='Y'` | Delete the mislocated `localbox<hash>` account, then redeploy.                   |

Bypass with `--skip-preflight` only if you understand the consequence.

## Quota / capacity errors at deploy time

```text
SkuNotAvailable / OperationNotAllowed: ... quota ...
```

You lack `Standard_E64s_v6` capacity in the region. Check and request:

```bash
az vm list-usage --location swedencentral -o table | grep -iE "ESv6"
```

Either request a quota increase (the 3-node default needs 64 vCPUs), or choose another
infra region with `-l <region>`.

## Password rejected

The Windows admin password must be 14–123 chars with 3 of lower/upper/digit/special, and
**must not contain `$`** (it breaks the in-VM LogonScript). `deploy.sh` validates this
before deploying.

## Artifacts fail to download inside the VM

The VM fetches `artifacts/` from this repo's raw URLs. If downloads fail:

- Confirm the repo is **public** and the path resolves, e.g.
  `curl -sfI https://raw.githubusercontent.com/jonathan-vella/apex-localops/main/artifacts/PowerShell/Bootstrap.ps1`
  should return `HTTP/2 200`.
- If you pinned `githubBranch` to a tag, confirm the tag exists and contains `artifacts/`.
- Outbound HTTPS egress from the VM goes through the NAT Gateway — confirm it deployed.

## Cluster build "succeeds" but tests fail

`DeploymentStatus` like `Tests succeeded: 9 Tests failed: 3` with
`DeploymentProgress = Failed` means the build reached the validation phase but the cluster
didn't fully form. Open `New-LocalBoxCluster.log` and search upward from the first
`Tests failed` line for the **first** hard error (often the witness-SA issue above or a
provider-registration race). `monitor.sh` tracks the authoritative
`Microsoft.AzureStackHCI/clusters` resource rather than this advisory tag.
