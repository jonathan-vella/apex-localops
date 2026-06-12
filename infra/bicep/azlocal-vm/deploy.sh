#!/usr/bin/env bash
#
# deploy.sh - Deploy ONE Windows Server 2025 VM on Azure Local with minimal effort.
#
# Wraps `az deployment group create` against main.bicep + main.bicepparam, handling
# password input, preflight lint, optional what-if/confirm, AD domain join, post-deploy
# verification, and cleanup. Idempotent: re-running is safe (ARM no-ops unchanged resources).
#
# Minimal effort:
#   export LOCALBOX_ADMIN_PASSWORD='<strong-password>'   # or let the script prompt you
#   ./deploy.sh                                          # deploys ws2025-<random>, no name clashes
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   -g, --resource-group RG   Target resource group (default: rg-azlocal-swc01).
#   -n, --name NAME           Exact VM name (no random suffix added). Required for --cleanup.
#       --prefix PREFIX       Base for the auto-generated name (default: ws2025).
#       --suffix VALUE        Use a specific suffix instead of a random one.
#       --no-suffix           Use the prefix as-is, with no random suffix.
#       --domain-join         Also join an Active Directory domain (uses the same password).
#       --domain FQDN         Domain to join with --domain-join (default: jumpstart.local).
#       --domain-user USER    Domain join account, no prefix (default: Administrator).
#   -w, --what-if             Preview changes only; deploy nothing.
#   -y, --yes                 Skip the confirmation prompt before deploying.
#       --cleanup             Delete the VM and its NIC + data disk, then exit (needs --name).
#   -h, --help                Show this help.
#
# Naming: unless you pass --name, the VM is named "<prefix>-<suffix>" (default prefix ws2025,
# suffix = 4 random hex chars, e.g. ws2025-3f9a). The final name must be <= 15 chars
# (NetBIOS / domain-join limit). The resolved name is printed before deploying.
#
# Prereqs: az login (operator) with rights on the resource group; Azure CLI. The admin
# password is taken from LOCALBOX_ADMIN_PASSWORD (never written to disk); if unset, the
# script prompts for it (no echo).

set -euo pipefail

RESOURCE_GROUP="rg-azlocal-swc01"
VM_NAME=""
NAME_PREFIX="ws2025"
SUFFIX=""
USE_SUFFIX=true
DOMAIN_JOIN=false
DOMAIN_FQDN="jumpstart.local"
DOMAIN_USER="Administrator"
WHATIF=false
ASSUME_YES=false
CLEANUP=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP="$SCRIPT_DIR/main.bicep"
PARAM="$SCRIPT_DIR/main.bicepparam"

usage() { awk 'NR==1{next} /^#/{sub(/^#[[:space:]]?/,"");print;next} {exit}' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="${2:?missing RG}"; shift 2 ;;
    -n|--name)           VM_NAME="${2:?missing name}"; shift 2 ;;
    --prefix)            NAME_PREFIX="${2:?missing prefix}"; shift 2 ;;
    --suffix)            SUFFIX="${2:?missing suffix}"; shift 2 ;;
    --no-suffix)         USE_SUFFIX=false; shift ;;
    --domain-join)       DOMAIN_JOIN=true; shift ;;
    --domain)            DOMAIN_FQDN="${2:?missing domain}"; DOMAIN_JOIN=true; shift 2 ;;
    --domain-user)       DOMAIN_USER="${2:?missing user}"; DOMAIN_JOIN=true; shift 2 ;;
    -w|--what-if|--whatif|--dry-run) WHATIF=true; shift ;;
    -y|--yes)            ASSUME_YES=true; shift ;;
    --cleanup)           CLEANUP=true; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# --- Preconditions -----------------------------------------------------------
command -v az >/dev/null 2>&1 || { echo "ERROR: az CLI not found." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: not logged in (run 'az login')." >&2; exit 1; }
[[ -f "$BICEP" && -f "$PARAM" ]] || { echo "ERROR: main.bicep / main.bicepparam not found next to this script." >&2; exit 1; }

# Resolve the VM name. An explicit --name is used verbatim; otherwise (deploy mode only)
# build "<prefix>[-<suffix>]" with a random 4-hex-char suffix so repeat demo runs never collide.
if [[ -z "$VM_NAME" ]] && ! $CLEANUP; then
  if $USE_SUFFIX; then
    [[ -n "$SUFFIX" ]] || SUFFIX="$(printf '%04x' "$RANDOM")"   # $RANDOM (0-32767) -> 4 hex chars, no SIGPIPE
    VM_NAME="${NAME_PREFIX}-${SUFFIX}"
  else
    VM_NAME="$NAME_PREFIX"
  fi
fi
if [[ -n "$VM_NAME" && ${#VM_NAME} -gt 15 ]]; then
  echo "ERROR: VM name '$VM_NAME' is ${#VM_NAME} chars; must be <= 15 (NetBIOS/domain-join limit). Use a shorter --prefix or --name." >&2
  exit 1
fi

SUBSCRIPTION="$(az account show --query id -o tsv)"

# --- Cleanup mode ------------------------------------------------------------
if $CLEANUP; then
  if [[ -z "$VM_NAME" ]]; then
    echo "ERROR: --cleanup needs an exact --name (auto-generated names are random and can't be guessed)." >&2
    exit 2
  fi
  echo "Cleanup: deleting VM '$VM_NAME' (+ NIC + data disk) in '$RESOURCE_GROUP'..."
  if ! $ASSUME_YES; then
    printf 'Delete %s and its NIC/disk? [y/N]: ' "$VM_NAME" >&2
    IFS= read -r reply || reply=""
    case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted." >&2; exit 1 ;; esac
  fi
  az extension add --name stack-hci-vm >/dev/null 2>&1 || true
  az stack-hci-vm delete             -g "$RESOURCE_GROUP" --name "$VM_NAME"        --yes 2>/dev/null || true
  az stack-hci-vm network nic delete -g "$RESOURCE_GROUP" --name "${VM_NAME}-nic"  --yes 2>/dev/null || true
  az stack-hci-vm disk delete        -g "$RESOURCE_GROUP" --name "${VM_NAME}-data" --yes 2>/dev/null || true
  echo "Cleanup done."
  exit 0
fi

# --- Password (never written to disk) ----------------------------------------
if [[ -z "${LOCALBOX_ADMIN_PASSWORD:-}" ]]; then
  printf 'Enter the VM admin password (input hidden): ' >&2
  IFS= read -rs LOCALBOX_ADMIN_PASSWORD || true
  echo >&2
  [[ -n "$LOCALBOX_ADMIN_PASSWORD" ]] || { echo "ERROR: a password is required." >&2; exit 1; }
fi
export LOCALBOX_ADMIN_PASSWORD   # main.bicepparam reads it via readEnvironmentVariable

# --- Build the parameter set (base param file + optional overrides) ----------
params=(--parameters "$PARAM" --parameters "name=$VM_NAME")
if $DOMAIN_JOIN; then
  params+=(--parameters
    "domainToJoin=$DOMAIN_FQDN"
    "domainJoinUserName=$DOMAIN_USER"
    "domainJoinPassword=$LOCALBOX_ADMIN_PASSWORD")
fi

echo "============================================================"
echo "  Subscription : $SUBSCRIPTION"
echo "  Resource grp : $RESOURCE_GROUP"
echo "  VM name      : $VM_NAME"
echo "  Template     : $BICEP"
$DOMAIN_JOIN && echo "  Domain join  : $DOMAIN_FQDN (as $DOMAIN_FQDN\\$DOMAIN_USER)"
echo "============================================================"

# --- Preflight: lint the template --------------------------------------------
echo "==> Validating template (az bicep build)..."
az bicep build --file "$BICEP" --stdout >/dev/null

# --- What-if -----------------------------------------------------------------
if $WHATIF; then
  echo "==> What-if (no changes will be made):"
  az deployment group what-if -g "$RESOURCE_GROUP" --template-file "$BICEP" "${params[@]}"
  exit 0
fi

if ! $ASSUME_YES; then
  printf 'Deploy VM "%s" to "%s"? [y/N]: ' "$VM_NAME" "$RESOURCE_GROUP" >&2
  IFS= read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted." >&2; exit 1 ;; esac
fi

# --- Deploy ------------------------------------------------------------------
DEP_NAME="azlocal-vm-$(date +%Y%m%d-%H%M%S)"
echo "==> Deploying ($DEP_NAME)..."
az deployment group create \
  -g "$RESOURCE_GROUP" --name "$DEP_NAME" \
  --template-file "$BICEP" "${params[@]}" \
  --query "{provisioningState:properties.provisioningState}" -o table

# --- Verify ------------------------------------------------------------------
echo "==> Verifying VM sizing + power state..."
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.HybridCompute/machines/$VM_NAME/providers/Microsoft.AzureStackHCI/virtualMachineInstances/default?api-version=2024-01-01" \
  --query "{provisioningState:properties.provisioningState, vmSize:properties.hardwareProfile.vmSize, cpu:properties.hardwareProfile.processors, memoryMB:properties.hardwareProfile.memoryMB, power:properties.status.powerState}" \
  -o table

if $DOMAIN_JOIN; then
  echo "==> Verifying domain join..."
  az rest --method get \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.HybridCompute/machines/$VM_NAME/extensions/domainJoinExtension?api-version=2025-01-13" \
    --query "{state:properties.provisioningState, message:properties.instanceView.status.message}" \
    -o table 2>/dev/null || echo "  (domain-join extension not reported yet; re-check shortly)"
fi

echo "Done. VM '$VM_NAME' deployed to '$RESOURCE_GROUP'."
