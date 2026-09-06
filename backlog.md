# Deployment backlog

## Resolved

### Node restart invalidated time synchronization before readiness validation

- **Observed:** 2026-09-06 during the clean self-hosted deployment at the `Readiness` stage.
- **Symptom:** The Software validator failed `AzStackHci_Software_NtpServer-Sync` only for
  `APEXLOCAL-N3`. The report showed `Local CMOS Clock` rather than `192.168.1.254`; N1 and N2
  passed both NTP consistency and synchronization checks.
- **Cause:** N3 completed its initial time configuration, then Windows initiated a clean restart
  as `NT AUTHORITY\\SYSTEM`. The validator ran before Windows Time re-synchronized after that
  restart. Later diagnostics proved the DC was reachable over UDP 123 and N3 synchronized with
  it without infrastructure changes.
- **Fix:** Nodes now use the documented NTP client peer mode (`0x8`). Before the Software
  validator runs, readiness records each node boot epoch, reconfigures and re-synchronizes any
  node that restarted or lacks a valid source, and requires a successful NTP stripchart response.
- **Prevention:** Do not treat the first successful time sync as final guest readiness. A node
  restart between setup and validation must restart the NTP convergence check.

### Domain controller reconnect raced post-promotion initialization

- **Observed:** 2026-09-06 during the clean self-hosted deployment, after the DC forest
  promotion rebooted `apexlocal-dc`.
- **Symptom:** PowerShell Direct first reported `A remote session might have ended` and then
  repeatedly reported `The credential is invalid` while reconnecting as
  `apexlocal\\Administrator`; the build remained at `DomainControllerReady`.
- **Cause:** The supplied credential was valid. The protected password file contained 16
  clean bytes, and a later read-only host diagnostic successfully authenticated with both
  `Administrator` and `apexlocal\\Administrator`. The failure was the post-promotion guest
  reboot/AD initialization window exceeding the reconnect wait.
- **Fix:** Extend the post-promotion PowerShell Direct wait from 30 to 45 minutes. The existing
  domain-controller health loop still verifies AD DS, DNS, NTDS, ADWS, and authoritative time
  before the build advances.
- **Prevention:** Treat the first post-promotion reconnect as a long-running readiness phase;
  do not rotate credentials or rebuild the deployment when both credential forms later work.

### Default artifact reference pointed at an unpublished tag

- **Observed:** 2026-09-06 during `./scripts/deploy-selfhosted.sh --what-if-only`.
- **Symptom:** Preflight failed all 14 runtime artifact checks with HTTP 404 for
  `jonathan-vella/apex-localops@v1.3.0-rc.1`; no billable resources were created.
- **Cause:** `v1.3.0-rc.1` was not a tag or branch on the remote repository.
- **Fix:** The deploy, staging, resume, and recovery scripts now use the repository's `main`
  branch by default. `--artifact-ref` remains available only to reproduce a particular revision.
- **Prevention:** Run `./scripts/deploy-selfhosted.sh --what-if-only` before a new deployment;
  its artifact reachability checks catch a missing or renamed runtime file before Azure resources
  are created.

### Password-file fallback was documented but not implemented

- **Observed:** 2026-09-06 before the authorized clean deployment.
- **Symptom:** `deploy-selfhosted.sh` would fail after preflight unless
  `LOCALSELF_ADMIN_PASSWORD` was manually exported, despite the runbook specifying the protected
  `~/.apex-localops/admin-password` file as the default source.
- **Cause:** The script only read `LOCALSELF_ADMIN_PASSWORD`.
- **Fix:** After preflight, it now reads the protected password file when no environment override
  is set, then validates the same password rules.
- **Prevention:** Keep the zero-input password-source assertion in the runbook and test it as
  part of the clean deployment path.
