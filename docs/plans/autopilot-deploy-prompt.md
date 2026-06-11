# Autopilot deploy prompt — apex-localops 3-node Azure Local (unattended)

**How to use:** open a NEW agent session, paste the entire **PROMPT TO PASTE** block below,
and on the `PASSWORD=` line put the real Windows admin password (throwaway env — fine to type
in chat, never commit it). Then let it run unattended.

**Why the password isn't in this file:** it is read into the `LOCALBOX_ADMIN_PASSWORD`
environment variable at runtime only. This file intentionally contains a placeholder so it is
safe to commit.

**Scope (locked):** exactly three stages — Azure infra → in-VM Azure Local build → cluster
deploy. No workload VMs, no AVD, no other changes.

---

## PROMPT TO PASTE

You are an autonomous deployment agent working in the apex-localops repo at
`/workspaces/apex-localops`. Run the task below **end to end WITHOUT ASKING ME ANYTHING**.
Make every decision yourself and keep going until either the SUCCESS or the FINAL-FAILURE
condition is reached. I am asleep — there will be no interaction.

PASSWORD=<put the Windows admin password here on this line, then delete this hint>

### Secret handling (critical)
- Read the password from the `PASSWORD=` line above. In the terminal, export it with SINGLE
  quotes so the `!` characters are safe:
  `export LOCALBOX_ADMIN_PASSWORD='<that value>'`
- After exporting, NEVER print it again, NEVER write it to any file, and NEVER `git commit`
  or `git push` (anything). It must not land on disk or in version control.

### Goal — exactly these three stages, nothing else
1. Deploy the Azure infrastructure (Bicep/ARM) for the 3-node LocalBox profile.
2. Let the in-VM Azure Local OS build run inside `LocalBox-Client`.
3. Deploy the Azure Local cluster (this happens automatically — `autoDeployClusterResource=true`).
Do NOT create workload VMs, AVD, logical networks, images, or anything beyond the cluster.

### Fixed configuration (do not change)
- Resource group `rg-localbox`, in the already-active subscription (expect **noalz**). If
  `az account show` fails, STOP and report — do NOT attempt to log in.
- Keep the defaults already in `infra/bicep/azlocal-js/main.bicepparam`: 3 nodes,
  `Standard_E64s_v6`, infra `swedencentral`, instance `westeurope`, latest-image
  auto-discovery, jumpbox on.

### Steps
1. `cd /workspaces/apex-localops`
2. Confirm login: `az account show`. If it fails → STOP + report.
3. Export the password (single quotes; do not echo): `export LOCALBOX_ADMIN_PASSWORD='<password>'`
4. Register providers (idempotent): `bash ./scripts/check-providers.sh`
5. Deploy infra unattended: `bash ./scripts/deploy.sh --yes --no-monitor`
   - Creates the RG, runs preflight + what-if, deploys ~29 resources (~18 min).
   - Confirm the ARM deployment `provisioningState = Succeeded` before continuing. If it is
     not Succeeded, treat as a failure (see Failure handling).
6. Monitor the in-VM build. Every ~15 minutes run: `bash ./scripts/monitor.sh --once`
   - Watch the `DeploymentProgress` tag advance through milestones (Installing WinGet… →
     Configure Hyper-V host → Creating … VMs → Deploying Azure Local cluster → Completed).
   - Budget up to **6 hours** total for the in-VM phase.
7. Determine the outcome AUTHORITATIVELY (do not trust the `DeploymentStatus` test tag alone —
   it is stale mid-build):
   - Run `az stack-hci cluster list -g rg-localbox -o table`.
   - SUCCESS = `provisioningState = Succeeded` AND `connectivityStatus = Connected`.
   - NOTE: plain `az resource list` does NOT surface the cluster — always use
     `az stack-hci cluster list`.

### Success condition
When the cluster is `Succeeded` + `Connected`: write a short report to
`docs/plans/autopilot-deploy-status.md` (NO secrets) covering what was deployed, the final
cluster state, and timings. Then STOP.

### Failure handling (full auto — ONE retry, then stop)
A failure = any of:
- `deploy.sh` exits non-zero, or the ARM deployment is not `Succeeded`;
- `localcluster-validate` or `localcluster-deploy` deployment shows `Failed`
  (`az deployment group list -g rg-localbox -o table`);
- the build stalls: `DeploymentProgress` unchanged for ~90 min (optionally corroborate with
  no `pwsh` build process on the VM via `az vm run-command`);
- the cluster is not `Succeeded` within the 6-hour budget.

On the FIRST confirmed failure:
1. Capture diagnostics into `docs/plans/autopilot-deploy-status.md` (NO secrets): failed
   deployment operations + their error messages
   (`az deployment operation group list -g rg-localbox -n <name> ...`), the RG tags, and the
   recent in-VM log tail (`bash ./scripts/monitor.sh --once --logs`).
2. Tear down: `bash ./scripts/cleanup.sh --yes`
3. Redeploy ONCE, starting again from step 4.

If the SECOND attempt also fails: STOP. Write a final failure report (root cause, error text,
where the logs are) to `docs/plans/autopilot-deploy-status.md`. Do NOT loop again.

### Hard constraints
- Never ask me anything; never wait for input.
- Never `git commit` / `git push`; never write the password to a file.
- Touch only `rg-localbox`. Make NO source-code changes. No VMs / AVD / extras.
- Leave the run report at `docs/plans/autopilot-deploy-status.md` for me to read in the morning.

---

## Quick reference (for me, the human)
- Stages run by this prompt: infra (~18 min) → in-VM build + cluster (~4–5 h).
- Cost while running ≈ $7,850/mo at 24×7; tear down later with `az group delete -n rg-localbox --yes`.
- Morning check: open `docs/plans/autopilot-deploy-status.md`, or run
  `az stack-hci cluster list -g rg-localbox -o table`.
