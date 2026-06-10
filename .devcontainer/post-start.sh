#!/usr/bin/env bash
# Runs on EVERY container start (devcontainer.json -> postStartCommand), not just
# on create/rebuild. Keeps the fast-moving CLIs current between rebuilds.
#
# Every step is best-effort by design: an offline start or a transient network
# error must never block the container. Failures are reported and swallowed
# (no `set -e`), and each network step is wrapped in `timeout` so a stuck
# download cannot hang container startup.
set -uo pipefail

echo "post-start: checking for tool updates..."

# --- Bicep CLI (az manages the binary under ~/.azure/bin; upgrade is a fast
#     no-op when already current). Addresses the "new Bicep release" notice.
if timeout 120 az bicep upgrade >/dev/null 2>&1; then
  echo "  bicep: $(az bicep version 2>/dev/null | head -n1)"
else
  echo "  bicep: skipped (offline or already current)"
fi

# --- Azure Developer CLI (azd): only reinstall when it reports a newer release,
#     via azd's own documented upgrade path. Passwordless sudo (already relied on
#     by onCreateCommand) lets the installer write to /usr/local/bin without a
#     prompt, so this stays non-interactive.
if azd version 2>&1 | grep -qi "update available"; then
  echo "  azd:   update available -> installing..."
  if timeout 180 bash -c 'curl -fsSL https://aka.ms/install-azd.sh | bash' >/dev/null 2>&1; then
    echo "  azd:   $(azd version 2>/dev/null | head -n1)"
  else
    echo "  azd:   update failed (will retry next start)"
  fi
else
  echo "  azd:   $(azd version 2>/dev/null | head -n1) (current)"
fi

echo "post-start: done."
