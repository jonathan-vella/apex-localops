# Deployment backlog

## Resolved

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
