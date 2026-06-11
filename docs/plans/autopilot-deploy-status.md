# Autopilot deploy status — apex-localops 3-node Azure Local

_Attempt #2 started: 2026-06-11 ~05:53 UTC · unattended autopilot · subscription `noalz`_

> No secrets in this file. Updated as the build progresses.

## Background
- **Attempt #1 (2026-06-10 21:06 UTC) FAILED** at the cluster cloud-deploy stage: the host VM
  was **forcefully shut down overnight**, so the Azure Local orchestrator lost contact with
  the nested nodes and cancelled with `DeployClusterOperationFailed` ("No Updates were
  received from the HCI device in the last 60 minutes"). Root cause was **environmental**
  (the shutdown), not config/code. The RG was torn down for a clean slate.
- Before redeploying, **Azure Hybrid Benefit** was added to both VMs (see Stage 1).

## Stage 1 — Azure infrastructure (ARM) ✅ SUCCEEDED
- Deployment `localbox-20260611-055310` → **Succeeded** (~06:13 UTC).
- **Azure Hybrid Benefit verified on live VMs**: `LocalBox-Client = Windows_Server`,
  `LocalBox-Mgmt = Windows_Client`.
- Profile: 3-node, `Standard_E64s_v6`, infra `swedencentral`, instance `westeurope`,
  jumpbox on, node image auto-discovery = latest.
- Note: `deploy.sh` preflight needed `LOCALBOX_SPN_PROVIDER_ID` set explicitly
  (`bd244008-…`) because Microsoft Graph (`az ad sp …`) lookups were unavailable this
  session. Value verified against attempt #1's successful deploy.

## Stage 2 — In-VM Azure Local build ⏳ IN PROGRESS
- Started ~06:14 UTC, clean (no stale tags). First milestone: "Restarting and installing
  WinGet packages…"
- Monitored via `scripts/monitor.sh` (5-min interval).

## Stage 3 — Cluster deploy ⏳ PENDING (automatic, autoDeployClusterResource=true)
- Authoritative success check: `az stack-hci cluster list -g rg-localbox -o table`
  → `provisioningState=Succeeded` AND `connectivityStatus=Connected`.

## Outcome
- _Pending — finalized when the cluster reaches Succeeded (or on failure)._

## Notes for later
- ⚠️ **Do not shut down / deallocate `LocalBox-Client` during the build** — that is what
  broke attempt #1. The cluster cloud-deploy needs the nested nodes alive for the full
  2–4 h cluster phase.
- Cost while running ≈ $7,850/mo at 24×7 (base rate; AHB removes the Windows surcharge).
  Tear down with `az group delete -n rg-localbox --yes`.
- Per autopilot rules: the one retry was effectively spent on the overnight shutdown, so on
  a genuine (non-environmental) failure this run captures diagnostics and STOPS rather than
  looping again.
