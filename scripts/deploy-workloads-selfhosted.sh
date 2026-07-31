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
# Nothing runs on the cluster host, so there is no run-command-extension wedge risk.
#
# Usage:
#   ./deploy-workloads-selfhosted.sh --stage <stage> [--what-if] [--yes]
#                         [--resource-group rg-apexlocal]
#
# Stages:
#   prereqs    Register Microsoft.EdgeMarketplace + assign ACM Resource Manager role (operator).
#   insights   Enable Azure Local cluster Insights (AMA+DCR on the 3 nodes) via Bicep (operator).
#   images     Ensure the 3 Marketplace images exist on the cluster (skips existing).
#   network    Ensure the AKS logical network exists; VMs reuse InfraLNET (skips existing).
#   wait       Poll the 3 images to Succeeded.
#   ws2025     Create + domain-join the two Windows Server 2025 VMs.
#   sql        Create + domain-join the SQL 2022 VM (defined for the future SQL plan).
#   avd-cp     Deploy the AVD control plane (host pool/workspace/app group) via Bicep (operator).
#   avd-host   Create + domain-join the Win11 session host and install the AVD agent.
#              Requires the registration token (auto-pulled from the host pool, or --token).
#   aks        Create the AKS (Arc) cluster on the AKS logical network (~30 min).
#              Deploy the sample app after it with scripts/deploy-aks-sample-app.sh.
#   all-vms    images + network + wait + ws2025 (NOT sql/avd/aks).
#
# Prereqs: az login (operator) with rights on the resource group; pwsh available. VM-creating
# stages need the admin password: export LOCALSELF_ADMIN_PASSWORD, or write it to a local
# git-ignored file (LOCALSELF_ADMIN_PASSWORD_FILE, default ~/.apex-localops/admin-password).

set -euo pipefail

RESOURCE_GROUP="rg-apexlocal"
STAGE=""
WHATIF=false
ASSUME_YES=false
TOKEN=""
SUBSCRIPTION=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKLOADS_DIR="$REPO_ROOT/artifacts/selfhosted/PowerShell/workloads"
AVD_BICEP="$REPO_ROOT/infra/bicep/azlocal-selfhosted/workloads/avd/main.bicep"
AVD_PARAM="$REPO_ROOT/infra/bicep/azlocal-selfhosted/workloads/avd/main.bicepparam"
INSIGHTS_BICEP="$REPO_ROOT/infra/bicep/azlocal-selfhosted/mgmt/insights.bicep"
AVD_HOST_POOL="apexlocal-hp01"

# Azure Local (Microsoft.AzureStackHCI) RP application id; its object id in THIS subscription is
# resolved at runtime for the ACM role assignment (marketplace images).
HCI_RP_APP_ID="1412d89f-b8a8-4111-b4fd-e82905cbd85d"
HCI_RP_OBJECT_ID="${LOCALSELF_HCI_RP_OBJECT_ID:-}"

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

# VM-creating stages need the admin password. Resolve it from LOCALSELF_ADMIN_PASSWORD, else a
# local git-ignored file (LOCALSELF_ADMIN_PASSWORD_FILE, default ~/.apex-localops/admin-password).
# The lab is gated by Azure MFA; the file is never committed and the env var is scrubbed on exit.
ADMIN_PASSWORD_FILE_DEFAULT="${HOME}/.apex-localops/admin-password"
require_password() {
  $WHATIF && return 0
  if [[ -n "${LOCALSELF_ADMIN_PASSWORD:-}" || -n "${WORKLOADS_ADMIN_PASSWORD:-}" ]]; then
    return 0
  fi
  local pw_file="${LOCALSELF_ADMIN_PASSWORD_FILE:-$ADMIN_PASSWORD_FILE_DEFAULT}"
  if [[ ! -f "$pw_file" ]]; then
    echo "ERROR: set LOCALSELF_ADMIN_PASSWORD, or write it to '$pw_file' (never committed)." >&2
    return 1
  fi
  local pw
  pw="$(tr -d '\r\n' < "$pw_file")"
  if (( ${#pw} < 12 || ${#pw} > 123 )); then
    echo "ERROR: admin password in '$pw_file' must be 12-123 characters." >&2
    return 1
  fi
  export LOCALSELF_ADMIN_PASSWORD="$pw"
  trap 'unset LOCALSELF_ADMIN_PASSWORD' EXIT
  echo "Using admin password from file: $pw_file"
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
  if [[ -z "$HCI_RP_OBJECT_ID" ]]; then
    HCI_RP_OBJECT_ID="$(az ad sp show --id "$HCI_RP_APP_ID" --query id -o tsv 2>/dev/null || true)"
  fi
  [[ -n "$HCI_RP_OBJECT_ID" ]] || { echo "ERROR: could not resolve the Azure Local RP object id (set LOCALSELF_HCI_RP_OBJECT_ID)." >&2; return 1; }
  echo "Assigning 'Azure Connected Machine Resource Manager' to HCI RP ($HCI_RP_OBJECT_ID) on the RG..."
  if $WHATIF; then
    echo "  [what-if] az role assignment create --assignee $HCI_RP_OBJECT_ID --role 'Azure Connected Machine Resource Manager' --scope $rgid"
  else
    confirm "Create the role assignment?" || return 1
    az role assignment create --assignee "$HCI_RP_OBJECT_ID" \
      --role "Azure Connected Machine Resource Manager" --scope "$rgid" 2>&1 | tail -3 || \
      echo "  (assignment may already exist or need UAA/Owner perms - verify manually)"
  fi
}

# --- Operator-side: Azure Local cluster Insights (Bicep) ---------------------
do_insights() {
  echo "=== Azure Local cluster Insights (Bicep, operator) ==="
  [[ -f "$INSIGHTS_BICEP" ]] || { echo "ERROR: $INSIGHTS_BICEP missing." >&2; return 1; }
  local wsName wsId nodes loc wsLoc cluster
  wsName="$(az resource list -g "$RESOURCE_GROUP" --resource-type Microsoft.OperationalInsights/workspaces --query '[0].name' -o tsv 2>/dev/null || true)"
  wsId="$(az resource list -g "$RESOURCE_GROUP" --resource-type Microsoft.OperationalInsights/workspaces --query '[0].id' -o tsv 2>/dev/null || true)"
  [[ -n "$wsName" && -n "$wsId" ]] || { echo "ERROR: Log Analytics workspace not found in $RESOURCE_GROUP." >&2; return 1; }
  # Resolve the cluster + its nodes generically (no hard-coded name prefix) so this works
  # for any self-hosted deployment.
  cluster="$(az stack-hci cluster list -g "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null || true)"
  [[ -n "$cluster" ]] || { echo "ERROR: no Azure Local cluster found in $RESOURCE_GROUP." >&2; return 1; }
  nodes="$(az stack-hci cluster show -g "$RESOURCE_GROUP" -n "$cluster" --query 'reportedProperties.nodes[].name' -o json 2>/dev/null || echo '[]')"
  [[ -n "$nodes" && "$nodes" != "[]" ]] || { echo "ERROR: no cluster nodes found for '$cluster' in $RESOURCE_GROUP." >&2; return 1; }
  loc="$(az connectedmachine list -g "$RESOURCE_GROUP" --query '[0].location' -o tsv 2>/dev/null || true)"
  [[ -n "$loc" ]] || loc="$(az group show -n "$RESOURCE_GROUP" --query location -o tsv 2>/dev/null || echo '')"
  wsLoc="$(az resource list -g "$RESOURCE_GROUP" --resource-type Microsoft.OperationalInsights/workspaces --query '[0].location' -o tsv 2>/dev/null || true)"
  [[ -n "$wsLoc" ]] || wsLoc="$loc"
  echo "Workspace: $wsName ($wsLoc)  Nodes: $nodes  Region: $loc"
  if $WHATIF; then
    az deployment group what-if -g "$RESOURCE_GROUP" --template-file "$INSIGHTS_BICEP" \
      --parameters nodeNames="$nodes" workspaceName="$wsName" workspaceResourceId="$wsId" location="$loc" dcrLocation="$wsLoc"
    return 0
  fi
  confirm "Enable cluster Insights (AMA+DCR on nodes) -> $wsName?" || return 1
  az deployment group create -g "$RESOURCE_GROUP" --name "insights-$(date +%Y%m%d-%H%M%S)" \
    --template-file "$INSIGHTS_BICEP" \
    --parameters nodeNames="$nodes" workspaceName="$wsName" workspaceResourceId="$wsId" location="$loc" dcrLocation="$wsLoc" -o table
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
  echo "  az desktopvirtualization hostpool retrieve-registration-token -g $RESOURCE_GROUP --name $AVD_HOST_POOL --query token -o tsv"
}

# --- Dispatch ----------------------------------------------------------------
case "$STAGE" in
  prereqs)        do_prereqs ;;
  insights)       do_insights ;;
  images|network|wait)
                  run_stage_local "$STAGE" ;;
  ws2025|sql)     require_password; run_stage_local "$STAGE" ;;
  aks)            # Kubernetes admin access can ONLY be granted at create time, so resolve the Entra
                  # group first; without it the cluster is created that nobody can use.
                  if [[ -z "${LOCALSELF_AKS_ADMIN_GROUP_ID:-}" ]]; then
                    LOCALSELF_AKS_ADMIN_GROUP_ID=$("$SCRIPT_DIR/ensure-admin-group.sh" --name 'ApexLocal-AKS-Admins' 2>/dev/null || true)
                    export LOCALSELF_AKS_ADMIN_GROUP_ID
                  fi
                  if [[ -n "${LOCALSELF_AKS_ADMIN_GROUP_ID:-}" ]]; then
                    echo "AKS Kubernetes admins: Entra group ${LOCALSELF_AKS_ADMIN_GROUP_ID}"
                  else
                    echo "WARNING: no Entra admin group resolved - the cluster will have no Kubernetes admin." >&2
                    echo "         Set LOCALSELF_AKS_ADMIN_GROUP_ID (or Aks.AdminGroupObjectId) and recreate to fix." >&2
                  fi
                  run_stage_local "$STAGE" ;;
  all-vms)        require_password; run_stage_local "all" ;;
  avd-cp)         do_avd_cp ;;
  avd-host)
                  require_password
                  if [[ -z "$TOKEN" ]]; then
                    echo "Pulling registration token from host pool $AVD_HOST_POOL..."
                    TOKEN="$(az desktopvirtualization hostpool retrieve-registration-token \
                      -g "$RESOURCE_GROUP" --name "$AVD_HOST_POOL" --query token -o tsv 2>/dev/null || true)"
                    if [[ -z "$TOKEN" ]]; then
                      # No active token (expired or never generated) — mint a fresh one valid 24h.
                      echo "No active token; generating a new one (valid ~24h)..."
                      _exp="$(date -u -d '+23 hours' +%Y-%m-%dT%H:%M:%SZ)"
                      az desktopvirtualization hostpool update -g "$RESOURCE_GROUP" --name "$AVD_HOST_POOL" \
                        --registration-info expiration-time="$_exp" registration-token-operation=Update -o none 2>/dev/null || true
                      TOKEN="$(az desktopvirtualization hostpool retrieve-registration-token \
                        -g "$RESOURCE_GROUP" --name "$AVD_HOST_POOL" --query token -o tsv 2>/dev/null || true)"
                    fi
                  fi
                  [[ -n "$TOKEN" ]] || { echo "ERROR: no registration token (deploy avd-cp first or pass --token)." >&2; exit 1; }
                  run_stage_local "avd-host" "-RegistrationToken '$TOKEN'" ;;
  *) echo "Unknown stage: $STAGE" >&2; usage; exit 2 ;;
esac

echo "Done: stage '$STAGE'."
