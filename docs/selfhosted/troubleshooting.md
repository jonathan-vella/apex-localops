# Troubleshoot the self-hosted profile

[Documentation home](../README.md) / Self-hosted / Troubleshooting

Use the resource-group `ApexProgress` and `ApexStatus` tags, private `logs` container, and
authoritative Azure Local resource state together. A progress tag alone is not proof that the
cluster is healthy.

## Collect evidence

```bash
./scripts/monitor-selfhosted.sh --once --logs -g rg-apexlocal
az stack-hci cluster list -g rg-apexlocal \
  --query "[0].{provisioning:provisioningState,connectivity:status}" -o table
az storage blob list --account-name <staging-account> --container-name logs \
  --auth-mode login -o table
```

Keep deployment and Environment Checker reports private. Do not place passwords, access tokens,
answer files, or unredacted customer identifiers in an issue or release note. See
[Self-hosted validation](validation.md) for the full evidence schema and the redacted-versus-private
rules.

## Recovery decision

| Failure point | Evidence | Supported action |
| --- | --- | --- |
| Artifact fetch | CSE log reports an unreachable immutable URL | Push a corrected candidate, clean up, and redeploy with its SHA. |
| Public IP creation reports `AllowBringYourOwnPublicIpAddress` not registered | ARM fails in `networkDeployment` before either VM exists | Run `check-providers-selfhosted.sh`; it registers the required Network feature and re-registers `Microsoft.Network`. Then clean up and redeploy. |
| ISO staging or integrity | `AwaitingIsos`, missing manifest, byte-length mismatch, or SHA-256 mismatch | Re-run `Upload-Isos.ps1` with both ISOs. Do not use raw blob upload. |
| `V:` or host disk geometry | Bootstrap fails before nested VMs exist | Confirm 8 host P30 (1024 GB) disks, then clean up and redeploy. |
| Nested VM `PausedCritical` / "critical IO errors" | A VM pauses and its API/agent goes unreachable | The S2D **pool** is full — thin CSV free space is misleading. Check `Get-StoragePool` `AllocatedSize` vs `Size`, then delete unused images/VMs (see [sizing](sizing.md#nested-storage-capacity)). |
| VHDX conversion | Partial VHDX removed or boot validation fails | Correct the ISO/build issue, then clean up and redeploy from a new candidate if code changed. |
| Router, NIC, Network ATC, AD, or time | Readiness log fails before all Arc machines connect | Use the private logs to fix the root cause, then clean up and redeploy. |
| Environment Checker or ARM Validate | Three Arc machines are `Connected`; validation report identifies the blocker | Fix external policy/RBAC if possible, then run `recover-selfhosted.sh --mode ValidateDeploy`. Code/config changes require a new candidate and clean RG. |
| ARM Deploy after successful Validate | Same candidate passed Validate, then Deploy failed transiently | Run `recover-selfhosted.sh --mode DeployOnly`. It rechecks nested VM, domain, LCM user, and Arc health first. |
| Cluster resource exists but is unhealthy | Azure Local resource is not `Succeeded` and `Connected` | Collect deployment operations and logs; use the recovery mode matching the known failure stage. |
| Secret cleanup | Machine environment or answer files still contain bootstrap material | Do not recover. Restrict access, collect private evidence, clean up the resource group, and rotate the lab password. |

## Inspect deployment operations

```bash
az deployment group list -g rg-apexlocal \
  --query "[].{name:name,state:properties.provisioningState,timestamp:properties.timestamp}" -o table
az deployment operation group list -g rg-apexlocal -n <deployment-name> \
  --query "[].{resource:properties.targetResource.resourceName,state:properties.provisioningState,message:properties.statusMessage.error.message}" \
  -o table
```

## Teardown

The only supported way to stop all billing and reset a pre-Arc or code/config failure is:

```bash
./scripts/cleanup-selfhosted.sh --resource-group rg-apexlocal
```

Deleting only the host VM leaves billable disks, Bastion, NAT Gateway, and projected resources.
