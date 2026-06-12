# BitLocker on Azure Local — PowerShell cheat-sheet

> Grounded in the vendored Microsoft doc
> [docs/upstream/azure-local/manage/manage-bitlocker.md](../../../../docs/upstream/azure-local/manage/manage-bitlocker.md).
> Run these on an Azure Local machine with local administrator credentials. Treat Microsoft Learn as
> canonical when the weekly mirror lags.

The `Get/Enable/Disable-ASBitLocker` cmdlets manage data-at-rest encryption for boot volumes and
Cluster Shared Volumes (CSVs).

## View encryption status

```powershell
# -PerNode requires CredSSP (remote PowerShell) or an RDP session; -Local is the default scope.
Get-ASBitLocker -VolumeType <BootVolume | ClusterSharedVolume> -<Local | PerNode>
```

## Enable BitLocker

```powershell
# -Cluster (all nodes) requires CredSSP. -MountPoint targets a specific CSV (e.g. C:\ClusterStorage\Volume1).
Enable-ASBitLocker -VolumeType <BootVolume | ClusterSharedVolume> -<Local | Cluster> [-MountPoint <path>]
```

## Disable BitLocker

```powershell
Disable-ASBitLocker -VolumeType <BootVolume | ClusterSharedVolume> -<Local | Cluster> [-MountPoint <path>]
```

| Parameter | Notes |
| --- | --- |
| `-VolumeType` | Required. `BootVolume` or `ClusterSharedVolume`. |
| `-Local` | Default scope. Acts on volumes owned by the local node. |
| `-Cluster` / `-PerNode` | All nodes. Requires CredSSP authentication. |
| `-MountPoint` | `-Local` only. Targets one CSV; omit to act on all CSVs owned by the local node. |

## Related

- Security baseline / secured-core: [docs/upstream/azure-local/manage/manage-secure-baseline.md](../../../../docs/upstream/azure-local/manage/manage-secure-baseline.md)
- Security features overview: [docs/upstream/azure-local/concepts/security-features.md](../../../../docs/upstream/azure-local/concepts/security-features.md)
