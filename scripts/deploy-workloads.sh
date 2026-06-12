#!/usr/bin/env bash
#
# deploy-workloads.sh - Human-invoked entry point to deploy post-cluster workloads
# (Windows Server 2025 VM, SQL 2022 VM, AVD session host) on the Azure Local cluster.
#
# This is ADDITIVE and SAFE: it never modifies the cluster or its infrastructure
# logical network. Run it ONLY after you've validated the cluster is operational.
# Each stage is idempotent (skips resources that already exist) and supports --what-if.
#
# Everything runs FROM THIS DEV CONTAINER with your operator `az` login - every action is
# a cloud/ARM call (stack-hci-vm for VM/disk/NIC/image/lnet via the custom location;
# Microsoft.HybridCompute machines/runCommands for in-guest steps; ARM/Bicep for AVD).
# Nothing runs on LocalBox-Client, so there is no run-command-extension wedge risk.
#
# Usage:
#   ./deploy-workloads.sh --stage <stage> [--what-if] [--yes]
#                         [--resource-group rg-azlocal-swc01]
#
# Stages:
#   prereqs    Register Microsoft.EdgeMarketplace + assign ACM Resource Manager role (operator).
#   images     Ensure the 3 Marketplace images exist on the cluster (skips existing).
#   network    Ensure the vlan200 logical network exists (skips existing).
#   wait       Poll the 3 images to Succeeded.
#   ws2025     Create + domain-join the Windows Server 2025 VM.
#   sql        Create + domain-join the SQL 2022 VM.
#   avd-cp     Deploy the AVD control plane (host pool/workspace/app group) via Bicep (operator).
#   avd-host   Create + domain-join the Win11 session host and install the AVD agent.
#              Requires the registration token (auto-pulled from the host pool, or --token).
#   all-vms    images + network + wait + ws2025 + sql (NOT avd).
#
# Prereqs: az login (operator) with rights on the resource group; pwsh available. VM-creating
# stages need the admin password in LOCALBOX_ADMIN_PASSWORD (never written to disk/committed).

set -euo pipefail

RESOURCE_GROUP="rg-azlocal-swc01"
STAGE=""
WHATIF=false
ASSUME_YES=false
TOKEN=""
SUBSCRIPTION=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKLOADS_DIR="$REPO_ROOT/artifacts/PowerShell/workloads"
AVD_BICEP="$REPO_ROOT/infra/bicep/azlocal-js/avd/main.bicep"
AVD_PARAM="$REPO_ROOT/infra/bicep/azlocal-js/avd/main.bicepparam"

# HCI Resource Provider app object id (Microsoft.AzureStackHCI RP) for the ACM role assignment.
SPN_PROVIDER_ID="${LOCALBOX_SPN_PROVIDER_ID:-bd244008-3ffc-40de-9cc9-032054b76e22}"

usage() { grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) STAGE="${2:?missing stage}"; shift 2 ;;
    --what-if|--whatif|--dry-run) WHATIF=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --token) TOKEN="${2:?missing token}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$STAGE" ]] || { echo "ERROR: --stage is required." >&2; usage; exit 2; }
command -v az >/dev/null 2>&1 || { echo "ERROR: az CLI not found." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: not logged in (run 'az login')." >&2; exit 1; }
SUBSCRIPTION="$(az account show --query id -o tsv)"

confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1" >&2
  IFS= read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) return 0 ;; *) echo "Aborted." >&2; return 1 ;; esac
}

# --- Run a stage of the orchestrator locally (pwsh, operator az context) ------
ORCHESTRATOR="$WORKLOADS_DIR/Deploy-AzLocalWorkloads.ps1"
run_stage_local() {
  local stage="$1"; shift
  local extra="$*"
  command -v pwsh >/dev/null 2>&1 || { echo "ERROR: pwsh not found (needed to run the orchestrator)." >&2; return 1; }
  [[ -f "$ORCHESTRATOR" ]] || { echo "ERROR: orchestrator missing: $ORCHESTRATOR" >&2; return 1; }
  local whatif_flag=""
  $WHATIF && whatif_flag="-WhatIf"
  echo "==> pwsh Deploy-AzLocalWorkloads.ps1 -Stage ${stage} ${whatif_flag} ${extra}"
  # Intentional word-splitting: $whatif_flag is one optional flag and $extra carries
  # additional orchestrator args (e.g. -RegistrationToken <tok>); both must split into argv.
  # shellcheck disable=SC2086
  pwsh -NoProfile -File "$ORCHESTRATOR" -Stage "$stage" $whatif_flag $extra
}

# VM-creating stages need the admin password in the environment (never on disk).
require_password() {
  $WHATIF && return 0
  if [[ -z "${LOCALBOX_ADMIN_PASSWORD:-}" && -z "${WORKLOADS_ADMIN_PASSWORD:-}" ]]; then
    echo "ERROR: export LOCALBOX_ADMIN_PASSWORD before VM stages (never committed)." >&2; return 1
  fi
}

# --- Operator-side: Phase 0 prerequisites ------------------------------------
do_prereqs() {
  echo "=== Phase 0 prereqs (operator) ==="
  echo "Subscription : $SUBSCRIPTION"
  echo "Resource grp : $RESOURCE_GROUP"
  local edge
  edge="$(az provider show --namespace Microsoft.EdgeMarketplace --query registrationState -o tsv 2>/dev/null || echo Unknown)"
  echo "Microsoft.EdgeMarketplace: $edge"
  if [[ "$edge" != "Registered" ]]; then
    confirm "Register Microsoft.EdgeMarketplace?" || return 1
    $WHATIF || az provider register --namespace Microsoft.EdgeMarketplace
  fi
  local rgid
  rgid="$(az group show -n "$RESOURCE_GROUP" --query id -o tsv)"
  echo "Assigning 'Azure Connected Machine Resource Manager' to HCI RP app ($SPN_PROVIDER_ID) on the RG..."
  if $WHATIF; then
    echo "  [what-if] az role assignment create --assignee $SPN_PROVIDER_ID --role 'Azure Connected Machine Resource Manager' --scope $rgid"
  else
    confirm "Create the role assignment?" || return 1
    az role assignment create --assignee "$SPN_PROVIDER_ID" \
      --role "Azure Connected Machine Resource Manager" --scope "$rgid" 2>&1 | tail -3 || \
      echo "  (assignment may already exist or need UAA/Owner perms - verify manually)"
  fi
}

# --- Operator-side: AVD control plane (Bicep) --------------------------------
do_avd_cp() {
  echo "=== AVD control plane (Bicep, operator) ==="
  [[ -f "$AVD_BICEP" ]] || { echo "ERROR: $AVD_BICEP missing." >&2; return 1; }
  if $WHATIF; then
    az deployment group what-if -g "$RESOURCE_GROUP" --template-file "$AVD_BICEP" --parameters "$AVD_PARAM"
    return 0
  fi
  confirm "Deploy AVD host pool / workspace / app group to $RESOURCE_GROUP?" || return 1
  az deployment group create -g "$RESOURCE_GROUP" --name "avd-controlplane-$(date +%Y%m%d-%H%M%S)" \
    --template-file "$AVD_BICEP" --parameters "$AVD_PARAM" -o table
  echo "Retrieve the registration token with:"
  echo "  az desktopvirtualization hostpool retrieve-registration-token -g $RESOURCE_GROUP --host-pool-name azl-hp01 --query token -o tsv"
}

# --- Dispatch ----------------------------------------------------------------
case "$STAGE" in
  prereqs)        do_prereqs ;;
  images|network|wait)
                  run_stage_local "$STAGE" ;;
  ws2025|sql)     require_password; run_stage_local "$STAGE" ;;
  all-vms)        require_password; run_stage_local "all" ;;
  avd-cp)         do_avd_cp ;;
  avd-host)
                  require_password
                  if [[ -z "$TOKEN" ]]; then
                    echo "Pulling registration token from host pool azl-hp01..."
                    TOKEN="$(az desktopvirtualization hostpool retrieve-registration-token \
                      -g "$RESOURCE_GROUP" --host-pool-name azl-hp01 --query token -o tsv 2>/dev/null || true)"
                  fi
                  [[ -n "$TOKEN" ]] || { echo "ERROR: no registration token (deploy avd-cp first or pass --token)." >&2; exit 1; }
                  run_stage_local "avd-host" "-RegistrationToken '$TOKEN'" ;;
  *) echo "Unknown stage: $STAGE" >&2; usage; exit 2 ;;
esac

echo "Done: stage '$STAGE'."
