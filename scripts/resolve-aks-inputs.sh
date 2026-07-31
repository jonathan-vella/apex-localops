#!/usr/bin/env bash
#
# resolve-aks-inputs.sh - Resolve the AKS-on-bare-metal deploy inputs from a Provisioned
# SFF machine, so the AKS deployment can run without manual data gathering.
#
# It discovers/derives and exports:
#   AKSBM_EDGE_MACHINE_NAME   name of the Provisioned SFF EdgeMachine (cluster deploys into its RG)
#   AKSBM_CONTROL_PLANE_IP    a control-plane IP in the machine's subnet (NOT the host IP)
#   AKSBM_SSH_PUBLIC_KEY      your SSH public key (from --ssh-key-file / env)
#   AKSBM_ADMIN_GROUP_ID      Entra admin group object id (auto-created if absent)
#
# Source it to export into your shell, or use --emit to print `export` lines:
#   source ./scripts/resolve-aks-inputs.sh --admin-group <guid>
#   eval "$(./scripts/resolve-aks-inputs.sh --admin-group <guid> --emit)"
#
# Or chain straight into the deploy:
#   ./scripts/resolve-aks-inputs.sh --admin-group <guid> --deploy
#
# Usage:
#   --resource-group <n>   SFF machine RG (default: rg-sff-azl-eus01)
#   --edge-machine <name>  override edge-machine discovery
#   --control-plane-ip <ip> override the control-plane IP (else derived from the subnet)
#   --machine-ip <ip>      the machine IP, to derive a CP IP in the same /24
#   --admin-group <guid>   Entra admin group object id (skip auto-create)
#   --admin-group-name <n> name for the auto-created/reused Entra group (default LocalSFF-AKS-Admins)
#   --ssh-key-file <path>  default: ~/.ssh/id_rsa.pub
#   --emit                 print `export VAR=...` lines (for eval)
#   --deploy               after resolving, run scripts/deploy-aks-baremetal.sh
#   --help

set -euo pipefail

RESOURCE_GROUP="rg-sff-azl-eus01"
EDGE_MACHINE_NAME="${AKSBM_EDGE_MACHINE_NAME:-}"
CONTROL_PLANE_IP="${AKSBM_CONTROL_PLANE_IP:-}"
MACHINE_IP=""
ADMIN_GROUP_ID="${AKSBM_ADMIN_GROUP_ID:-}"
ADMIN_GROUP_NAME="${AKSBM_ADMIN_GROUP_NAME:-LocalSFF-AKS-Admins}"
SSH_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
EMIT=false
DEPLOY=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --edge-machine) EDGE_MACHINE_NAME="${2:?missing value}"; shift 2 ;;
    --control-plane-ip) CONTROL_PLANE_IP="${2:?missing value}"; shift 2 ;;
    --machine-ip) MACHINE_IP="${2:?missing value}"; shift 2 ;;
    --admin-group) ADMIN_GROUP_ID="${2:?missing value}"; shift 2 ;;
    --admin-group-name) ADMIN_GROUP_NAME="${2:?missing value}"; shift 2 ;;
    --ssh-key-file) SSH_KEY_FILE="${2:?missing value}"; shift 2 ;;
    --emit) EMIT=true; shift ;;
    --deploy) DEPLOY=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; return 0 2>/dev/null || exit 0 ;;
    *) echo "Unknown argument: $1" >&2; return 2 2>/dev/null || exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; return 1 2>/dev/null || exit 1; }

# --- 1. Edge machine ---
if [[ -z "$EDGE_MACHINE_NAME" ]]; then
  # Discover the (first) EdgeMachine in the SFF resource group.
  EDGE_MACHINE_NAME=$(az resource list -g "$RESOURCE_GROUP" \
    --resource-type "Microsoft.AzureStackHCI/edgeMachines" --query "[0].name" -o tsv 2>/dev/null || true)
fi
if [[ -z "$EDGE_MACHINE_NAME" || "$EDGE_MACHINE_NAME" == "None" ]]; then
  echo "WARNING: could not discover an EdgeMachine in $RESOURCE_GROUP. Pass --edge-machine <name>." >&2
  echo "         (It exists only after the SFF machine reaches 'Provisioned'.)" >&2
fi

# --- 2. Control plane IP ---
# Derive a candidate in the machine's /24 if not supplied. The control-plane IP must be a
# reserved, unused IP in the machine's subnet and NOT the machine's own IP.
if [[ -z "$CONTROL_PLANE_IP" ]]; then
  if [[ -z "$MACHINE_IP" ]]; then
    # Try to read the machine IP from the edge-machine resource.
    MACHINE_IP=$(az resource list -g "$RESOURCE_GROUP" \
      --resource-type "Microsoft.AzureStackHCI/edgeMachines" \
      --query "[0].properties.ipAddress" -o tsv 2>/dev/null || true)
  fi
  if [[ "$MACHINE_IP" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    prefix="${BASH_REMATCH[1]}"
    host="${BASH_REMATCH[2]}"
    # Pick a high-but-valid host octet distinct from the machine; reserve it in DHCP.
    cp_host=$(( host >= 240 ? host - 5 : host + 10 ))
    (( cp_host < 2 )) && cp_host=240
    (( cp_host > 254 )) && cp_host=240
    CONTROL_PLANE_IP="${prefix}.${cp_host}"
    echo "Derived candidate control-plane IP ${CONTROL_PLANE_IP} from machine IP ${MACHINE_IP}." >&2
    echo "  >> RESERVE this IP in DHCP (or confirm it is free) before deploying. <<" >&2
  else
    echo "WARNING: could not derive a control-plane IP. Pass --control-plane-ip <ip> (reserved, same subnet, not the host IP)." >&2
  fi
fi

# --- 3. SSH public key ---
if [[ -z "${AKSBM_SSH_PUBLIC_KEY:-}" && -f "$SSH_KEY_FILE" ]]; then
  AKSBM_SSH_PUBLIC_KEY="$(cat "$SSH_KEY_FILE")"
fi

# --- 4. Admin group: resolve-or-create the Entra security group (idempotent) ---
if [[ -z "$ADMIN_GROUP_ID" ]]; then
  echo "No admin group id supplied; ensuring Entra group '${ADMIN_GROUP_NAME}' exists..." >&2
  ADMIN_GROUP_ID=$("$SCRIPT_DIR/ensure-admin-group.sh" --name "$ADMIN_GROUP_NAME" 2>>/dev/stderr || true)
  if [[ -z "$ADMIN_GROUP_ID" ]]; then
    echo "WARNING: could not resolve or create the Entra admin group. Pass --admin-group <guid>," >&2
    echo "         or have an administrator create '${ADMIN_GROUP_NAME}' and re-run." >&2
  fi
fi

export AKSBM_EDGE_MACHINE_NAME="$EDGE_MACHINE_NAME"
export AKSBM_CONTROL_PLANE_IP="$CONTROL_PLANE_IP"
export AKSBM_ADMIN_GROUP_ID="$ADMIN_GROUP_ID"
[[ -n "${AKSBM_SSH_PUBLIC_KEY:-}" ]] && export AKSBM_SSH_PUBLIC_KEY

echo "Resolved AKS on bare metal inputs:" >&2
echo "  AKSBM_EDGE_MACHINE_NAME  = ${AKSBM_EDGE_MACHINE_NAME:-<unset>}" >&2
echo "  AKSBM_CONTROL_PLANE_IP   = ${AKSBM_CONTROL_PLANE_IP:-<unset>}" >&2
echo "  AKSBM_ADMIN_GROUP_ID     = ${AKSBM_ADMIN_GROUP_ID:-<unset>}" >&2
echo "  AKSBM_SSH_PUBLIC_KEY     = ${AKSBM_SSH_PUBLIC_KEY:+<set>}" >&2

if [[ "$EMIT" == "true" ]]; then
  echo "export AKSBM_EDGE_MACHINE_NAME='${AKSBM_EDGE_MACHINE_NAME}'"
  echo "export AKSBM_CONTROL_PLANE_IP='${AKSBM_CONTROL_PLANE_IP}'"
  echo "export AKSBM_ADMIN_GROUP_ID='${AKSBM_ADMIN_GROUP_ID}'"
  [[ -n "${AKSBM_SSH_PUBLIC_KEY:-}" ]] && echo "export AKSBM_SSH_PUBLIC_KEY='${AKSBM_SSH_PUBLIC_KEY}'"
fi

if [[ "$DEPLOY" == "true" ]]; then
  echo "Chaining into deploy-aks-baremetal.sh ..." >&2
  "$SCRIPT_DIR/deploy-aks-baremetal.sh"
fi
