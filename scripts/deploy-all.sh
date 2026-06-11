#!/usr/bin/env bash
#
# deploy-all.sh - End-to-end, as-zero-touch-as-possible orchestrator for the full chain:
#
#   SFF host build -> nested ROE VM -> (auto) ownership voucher -> Azure machine
#   provisioning -> AKS on bare metal -> kubectl.
#
# It chains the per-stage scripts with tag/resource-gated waits so the only human
# touchpoints are the irreducible ones (see docs/sff-zero-touch.md):
#   * one-time-ever: stage the ROE ISO + Configurator App into the staging account
#   * per-deploy: complete the portal "Add machine from voucher" step IF the SFF
#     machine-provisioning CLI isn't available (provision-machine.sh detects this and
#     waits for you; everything else is automatic)
#
# Stages (each can be skipped to resume a partial run):
#   1 providers   scripts/check-providers-sff.sh
#   2 sff         scripts/deploy-sff.sh           (waits for SffProgress=RoeSucceeded)
#   3 voucher     wait for SffProgress=VoucherStored (auto SSH extraction on the host)
#   4 provision   scripts/provision-machine.sh    (auto or guided; waits for Provisioned)
#   5 aks         scripts/resolve-aks-inputs.sh + scripts/deploy-aks-baremetal.sh
#   6 connect     scripts/connect-aks-baremetal.sh --get-nodes
#
# Usage:
#   ./deploy-all.sh --admin-group <guid>                 # full chain (explicit group)
#   ./deploy-all.sh --admin-group-name "My AKS Admins"   # auto-create/reuse a named group
#   ./deploy-all.sh --from <stage> --to <stage>          # run a subset (by name or number)
#   ./deploy-all.sh --skip providers,sff                 # skip stages
#   ./deploy-all.sh --resource-group rg-localsff
#   ./deploy-all.sh --aks-resource-group rg-localsff
#   ./deploy-all.sh --dry-run                            # print the plan, run nothing
#   ./deploy-all.sh --help
#
# Prerequisites: az login. The Windows password flows through LOCALSFF_ADMIN_PASSWORD
# (deploy-sff.sh prompts if unset). The Entra admin group is auto-created (idempotent: an
# existing group of the same name is reused) unless you pass an explicit --admin-group.
# and your SSH key (resolve-aks-inputs.sh handles the rest).

set -euo pipefail

RESOURCE_GROUP="rg-localsff"
# The AKS cluster deploys into the SAME resource group as the Provisioned EdgeMachine
# (the template references it by name within the deployment RG), so it tracks the SFF RG
# unless explicitly overridden with --aks-resource-group. Empty here => resolved after parsing.
AKS_RESOURCE_GROUP=""
ADMIN_GROUP_ID="${AKSBM_ADMIN_GROUP_ID:-}"
ADMIN_GROUP_NAME="${AKSBM_ADMIN_GROUP_NAME:-LocalSFF-AKS-Admins}"
SSH_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
FROM_STAGE="providers"
TO_STAGE="connect"
SKIP_CSV=""
DRY_RUN=false
VOUCHER_WAIT_SECONDS=21600   # 6h: the in-VM build + auto voucher extraction

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ordered stage list.
STAGES=(providers sff voucher provision aks connect)
stage_index() { local s="$1" i; for i in "${!STAGES[@]}"; do [[ "${STAGES[$i]}" == "$s" ]] && { echo "$i"; return; }; done; echo "-1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM_STAGE="${2:?missing value}"; shift 2 ;;
    --to) TO_STAGE="${2:?missing value}"; shift 2 ;;
    --skip) SKIP_CSV="${2:?missing value}"; shift 2 ;;
    --admin-group) ADMIN_GROUP_ID="${2:?missing value}"; shift 2 ;;
    --admin-group-name) ADMIN_GROUP_NAME="${2:?missing value}"; shift 2 ;;
    --ssh-key-file) SSH_KEY_FILE="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --aks-resource-group) AKS_RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# The AKS cluster must live in the EdgeMachine's resource group; default it to the SFF RG.
AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-$RESOURCE_GROUP}"

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

# Allow numeric stage names too.
[[ "$FROM_STAGE" =~ ^[0-9]+$ ]] && FROM_STAGE="${STAGES[$((FROM_STAGE-1))]:-$FROM_STAGE}"
[[ "$TO_STAGE" =~ ^[0-9]+$ ]] && TO_STAGE="${STAGES[$((TO_STAGE-1))]:-$TO_STAGE}"
FROM_IDX=$(stage_index "$FROM_STAGE"); TO_IDX=$(stage_index "$TO_STAGE")
[[ "$FROM_IDX" -ge 0 ]] || { echo "ERROR: unknown --from stage '$FROM_STAGE'. One of: ${STAGES[*]}" >&2; exit 2; }
[[ "$TO_IDX" -ge 0 ]] || { echo "ERROR: unknown --to stage '$TO_STAGE'. One of: ${STAGES[*]}" >&2; exit 2; }

is_skipped() { [[ ",$SKIP_CSV," == *",$1,"* ]]; }
should_run() {
  local idx; idx=$(stage_index "$1")
  (( idx >= FROM_IDX && idx <= TO_IDX )) && ! is_skipped "$1"
}

banner() {
  echo
  echo "════════════════════════════════════════════════════════════════════"
  echo "  STAGE: $1"
  echo "════════════════════════════════════════════════════════════════════"
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then echo "  [dry-run] $*"; return 0; fi
  echo "  + $*"
  "$@"
}

# Wait for a SffProgress resource-group tag to reach one of the given values.
wait_for_tag() {
  local want_csv="$1" timeout="$2" deadline tag
  deadline=$(( $(date +%s) + timeout ))
  echo "Waiting for SffProgress in {$want_csv} (up to $((timeout/60)) min)..."
  while true; do
    tag=$(az group show -n "$RESOURCE_GROUP" --query "tags.SffProgress" -o tsv 2>/dev/null || true)
    echo "  SffProgress = ${tag:-<none>}"
    case ",$want_csv," in *",$tag,"*) echo "  reached '$tag'."; return 0 ;; esac
    if [[ "$tag" == "Failed" ]]; then echo "❌ SffProgress=Failed. Inspect: ./scripts/monitor-sff.sh --once --logs" >&2; return 1; fi
    if [[ $(date +%s) -ge $deadline ]]; then echo "⏱  Timed out waiting for {$want_csv}." >&2; return 2; fi
    sleep 60
  done
}

echo "Plan: stages ${FROM_STAGE}..${TO_STAGE}${SKIP_CSV:+ (skipping: $SKIP_CSV)}"
echo "SFF RG: $RESOURCE_GROUP   AKS RG: $AKS_RESOURCE_GROUP"
$DRY_RUN && echo "(dry-run: no commands will be executed)"

# --- Stage 1: providers + ZTP feature ---
if should_run providers; then
  banner "providers (check-providers-sff.sh)"
  run "$SCRIPT_DIR/check-providers-sff.sh"
fi

# --- Stage 2: SFF host build (waits internally for the cluster/ROE phase via its monitor) ---
if should_run sff; then
  banner "sff (deploy-sff.sh)"
  run "$SCRIPT_DIR/deploy-sff.sh" --resource-group "$RESOURCE_GROUP" --no-monitor
  if [[ "$DRY_RUN" != "true" ]]; then
    echo "ACTION REQUIRED (one-time-ever): stage roe.iso + configurator.msi into the staging"
    echo "account from an Azure resource (jumpbox/Cloud Shell). See docs/sff-quickstart.md §4."
    wait_for_tag "RoeSucceeded,VoucherStored" "$VOUCHER_WAIT_SECONDS"
  fi
fi

# --- Stage 3: ownership voucher (auto SSH extraction on the host) ---
if should_run voucher; then
  banner "voucher (automatic SSH extraction -> Key Vault)"
  if [[ "$DRY_RUN" != "true" ]]; then
    # If the host already auto-extracted it, this returns immediately.
    if ! wait_for_tag "VoucherStored" 900; then
      echo "Voucher not auto-stored. Use the guided path (docs/sff-runbook.md §1-2), then re-run --from provision." >&2
      exit 1
    fi
  fi
fi

# --- Stage 4: Azure machine provisioning (auto if preview CLI present, else guided + wait) ---
if should_run provision; then
  banner "provision (provision-machine.sh)"
  run "$SCRIPT_DIR/provision-machine.sh" --resource-group "$RESOURCE_GROUP"
fi

# --- Stage 5: AKS on bare metal (resolve inputs, then deploy) ---
if should_run aks; then
  banner "aks (resolve-aks-inputs.sh + deploy-aks-baremetal.sh)"
  # The Entra admin group is auto-created by resolve-aks-inputs.sh (idempotent: reuses an
  # existing group of the same name). Pass an explicit id with --admin-group to override.
  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$ADMIN_GROUP_ID" ]]; then
      echo "  [dry-run] resolve-aks-inputs.sh --admin-group $ADMIN_GROUP_ID --deploy"
    else
      echo "  [dry-run] resolve-aks-inputs.sh --admin-group-name '$ADMIN_GROUP_NAME' (ensure/create) --deploy"
    fi
  else
    # shellcheck disable=SC1090,SC1091
    source "$SCRIPT_DIR/resolve-aks-inputs.sh" --resource-group "$RESOURCE_GROUP" \
      ${ADMIN_GROUP_ID:+--admin-group "$ADMIN_GROUP_ID"} \
      --admin-group-name "$ADMIN_GROUP_NAME" --ssh-key-file "$SSH_KEY_FILE"
    "$SCRIPT_DIR/deploy-aks-baremetal.sh" --resource-group "$AKS_RESOURCE_GROUP" --yes
  fi
fi

# --- Stage 6: connect ---
if should_run connect; then
  banner "connect (connect-aks-baremetal.sh --get-nodes)"
  run "$SCRIPT_DIR/connect-aks-baremetal.sh" --resource-group "$AKS_RESOURCE_GROUP" --get-nodes
fi

echo
echo "deploy-all.sh complete (stages ${FROM_STAGE}..${TO_STAGE})."
