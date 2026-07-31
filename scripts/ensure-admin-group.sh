#!/usr/bin/env bash
#
# ensure-admin-group.sh - Resolve-or-create the Microsoft Entra ID security group used for
# AKS-on-bare-metal cluster admin access (Azure RBAC for Kubernetes).
#
# Idempotent: if a group with the given display name already exists, its object id is
# reused; otherwise the group is created. By default the signed-in user is added as a
# member so you immediately have cluster-admin access.
#
# The group object id is printed to STDOUT (so callers can capture it); all diagnostics go
# to STDERR. With --emit it also prints an `export AKSBM_ADMIN_GROUP_ID=...` line.
#
# Usage:
#   ./ensure-admin-group.sh                       # default name, add self, print object id
#   ./ensure-admin-group.sh --name "My AKS Admins"
#   ./ensure-admin-group.sh --no-add-self         # don't add the signed-in user
#   ./ensure-admin-group.sh --emit                # print `export AKSBM_ADMIN_GROUP_ID=...`
#   ./ensure-admin-group.sh --help
#
# Requires directory permissions to create groups (e.g. Groups Administrator, or a tenant
# that allows users to create security groups). If creation is not permitted, the script
# prints a clear message and exits non-zero so you can pass an existing --admin-group id.
#
# Prerequisites: az login.

set -euo pipefail

GROUP_NAME="LocalSFF-AKS-Admins"
ADD_SELF=true
EMIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) GROUP_NAME="${2:?missing value}"; shift 2 ;;
    --no-add-self) ADD_SELF=false; shift ;;
    --emit) EMIT=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

# --- 1. Resolve an existing group by display name (reuse if present) ---
group_id=$(az ad group list --filter "displayName eq '${GROUP_NAME}'" --query "[0].id" -o tsv 2>/dev/null || true)

if [[ -n "$group_id" && "$group_id" != "None" ]]; then
  echo "Reusing existing Entra group '${GROUP_NAME}' (${group_id})." >&2
else
  # --- 2. Create it (mailNickname must be alphanumeric, no spaces) ---
  mail_nickname=$(printf '%s' "$GROUP_NAME" | tr -cd '[:alnum:]')
  [[ -z "$mail_nickname" ]] && mail_nickname="aksadmins"
  echo "Creating Entra security group '${GROUP_NAME}'..." >&2
  group_id=$(az ad group create --display-name "$GROUP_NAME" --mail-nickname "$mail_nickname" \
    --query id -o tsv 2>/dev/null || true)
  if [[ -z "$group_id" || "$group_id" == "None" ]]; then
    echo "ERROR: could not create the Entra group '${GROUP_NAME}'." >&2
    echo "       You likely lack directory permissions to create groups. Either ask an" >&2
    echo "       administrator to create it, or pass an existing group with --admin-group <id>." >&2
    exit 1
  fi
  echo "Created Entra group '${GROUP_NAME}' (${group_id})." >&2
fi

# --- 3. Add the signed-in user as a member (idempotent; best-effort) ---
if [[ "$ADD_SELF" == "true" ]]; then
  user_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  if [[ -n "$user_id" && "$user_id" != "None" ]]; then
    is_member=$(az ad group member check --group "$group_id" --member-id "$user_id" \
      --query value -o tsv 2>/dev/null || echo "false")
    if [[ "$is_member" == "true" ]]; then
      echo "Signed-in user is already a member of '${GROUP_NAME}'." >&2
    else
      if az ad group member add --group "$group_id" --member-id "$user_id" >/dev/null 2>&1; then
        echo "Added the signed-in user to '${GROUP_NAME}'." >&2
      else
        echo "Note: could not add the signed-in user to the group (continuing)." >&2
      fi
    fi
  else
    echo "Note: no signed-in user object id (service principal login?); skipping self-add." >&2
  fi
fi

# --- 4. Emit the object id ---
if [[ "$EMIT" == "true" ]]; then
  echo "export AKSBM_ADMIN_GROUP_ID='${group_id}'"
else
  echo "$group_id"
fi
