# Update Azure Local via PowerShell — cheat-sheet

> Grounded in the vendored Microsoft doc
> [docs/upstream/azure-local/update/update-via-powershell-23h2.md](../../../../docs/upstream/azure-local/update/update-via-powershell-23h2.md).
> Run these in a remote PowerShell session to the Azure Local instance. Treat Microsoft Learn as
> canonical when the weekly mirror lags. Prefer Azure Update Manager (portal) for routine updates;
> use PowerShell for limited-connectivity or scripted flows.

## Discover available updates

```powershell
Get-SolutionUpdate
```

The update service discovers updates asynchronously — you may need to run it more than once.

## Inspect a specific version

```powershell
$Update = Get-SolutionUpdate | Where-Object version -eq "<version string>"   # e.g. "10.2405.0.23"
$Update.State
```

## Start an update

`Start-SolutionUpdate` downloads, runs readiness checks, then installs. Save `$InstanceId` for
troubleshooting.

```powershell
$InstanceId = Get-SolutionUpdate -Id <ResourceId> | Start-SolutionUpdate
```

## Track progress

Connect the session to the **last** server in the cluster (it reboots last), or track in the portal.

```powershell
Get-SolutionUpdate -Id <ResourceId> | Format-Table Version,State,UpdateStateProperties,HealthState
```

States progress: `Downloading` -> `Preparing` -> `HealthChecking` -> `Installing` -> `Installed`.
If `State` is `HealthCheckFailed`, resolve readiness checks before continuing.

## Resume a failed update

```powershell
# Resume after a failure
Get-SolutionUpdate -Id <ResourceId> | Start-SolutionUpdate

# Resume when readiness checks are only in a Warning state
Get-SolutionUpdate -Id <ResourceId> | Start-SolutionUpdate -IgnoreWarnings
```

## Related

- Update phases and readiness checks: [docs/upstream/azure-local/update/update-phases-23h2.md](../../../../docs/upstream/azure-local/update/update-phases-23h2.md)
- Offline / limited connectivity: [docs/upstream/azure-local/update/import-discover-updates-offline-23h2.md](../../../../docs/upstream/azure-local/update/import-discover-updates-offline-23h2.md)
- Troubleshooting: [docs/upstream/azure-local/update/update-troubleshooting-23h2.md](../../../../docs/upstream/azure-local/update/update-troubleshooting-23h2.md)
