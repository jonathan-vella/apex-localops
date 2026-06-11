#!/usr/bin/env bash
#
# deploy-aks-baremetal.sh - Deploy an AKS on bare metal (preview) cluster onto a
# provisioned Azure Local Small Form Factor (SFF) Arc-enabled machine.
#
# This is the DOWNSTREAM step after the SFF machine is provisioned from the Azure
# portal (docs/sff-runbook.md). It needs values that only exist once the edge
# machine is "Provisioned":
#
#   AKSBM_EDGE_MACHINE_NAME   name of the Provisioned SFF EdgeMachine (in the target RG)
#   AKSBM_CONTROL_PLANE_IP    a reserved IP in the machine's subnet (NOT the host IP)
#   AKSBM_SSH_PUBLIC_KEY      your SSH public key contents (else read from --ssh-key-file)
#   AKSBM_ADMIN_GROUP_ID      Entra security group object id for cluster admins
#                             (auto-created/reused via ensure-admin-group.sh if absent)
#   AKSBM_KUBERNETES_VERSION  (optional) override the default Kubernetes version
#   AKSBM_LOG_ANALYTICS_WORKSPACE_ID  (optional) workspace ARM id for container monitoring
#
# The cluster deploys into the SAME resource group as the Provisioned EdgeMachine
# (the template references the machine by name within the deployment RG). Use -g
# to target that resource group.
#
# Usage:
#   ./deploy-aks-baremetal.sh                       # preflight, what-if, confirm, deploy
#   ./deploy-aks-baremetal.sh --what-if-only        # preview only (no deploy)
#   ./deploy-aks-baremetal.sh --yes                 # skip the confirmation prompt
#   ./deploy-aks-baremetal.sh --skip-preflight      # skip pre-deployment checks
#   ./deploy-aks-baremetal.sh --ssh-key-file <p>    # default: ~/.ssh/id_rsa.pub
#   ./deploy-aks-baremetal.sh --admin-group <id>    # use a specific Entra group object id
#   ./deploy-aks-baremetal.sh --admin-group-name <n># name for the auto-created/reused group
#   ./deploy-aks-baremetal.sh --resource-group <n>  # default: rg-localsff (EdgeMachine's RG)
#   ./deploy-aks-baremetal.sh --location <region>   # default: eastus (preview-only region)
#   ./deploy-aks-baremetal.sh --help
#
# Prerequisites: az login; a Provisioned SFF edge machine; providers registered
# (scripts/check-providers-sff.sh covers them); the connectedk8s CLI extension
# (this script installs it if missing).

set -euo pipefail

# Must be the resource group that contains the Provisioned SFF EdgeMachine — the
# template references the machine by name within the deployment resource group.
RESOURCE_GROUP="rg-localsff"
LOCATION="eastus"
WHATIF_ONLY=false
ASSUME_YES=false
SKIP_PREFLIGHT=false
SSH_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
ADMIN_GROUP_NAME="${AKSBM_ADMIN_GROUP_NAME:-LocalSFF-AKS-Admins}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$REPO_ROOT/infra/bicep/aks-baremetal/main.bicep"
PARAMS="$REPO_ROOT/infra/bicep/aks-baremetal/main.bicepparam"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --what-if-only) WHATIF_ONLY=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --skip-preflight) SKIP_PREFLIGHT=true; shift ;;
    --ssh-key-file) SSH_KEY_FILE="${2:?missing value}"; shift 2 ;;
    --admin-group) AKSBM_ADMIN_GROUP_ID="${2:?missing value}"; export AKSBM_ADMIN_GROUP_ID; shift 2 ;;
    --admin-group-name) ADMIN_GROUP_NAME="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --location|-l) LOCATION="${2:?missing value}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "ERROR: template not found: $TEMPLATE" >&2; exit 1; }
[[ -f "$PARAMS" ]] || { echo "ERROR: params not found: $PARAMS" >&2; exit 1; }

# --- Resolve the SSH public key (env var wins; else the key file) ---
if [[ -z "${AKSBM_SSH_PUBLIC_KEY:-}" ]]; then
  if [[ -f "$SSH_KEY_FILE" ]]; then
    AKSBM_SSH_PUBLIC_KEY="$(cat "$SSH_KEY_FILE")"
    export AKSBM_SSH_PUBLIC_KEY
    echo "Using SSH public key from $SSH_KEY_FILE"
  fi
fi

# --- Prompt for any missing required inputs (none are secrets) ---
prompt_if_empty() {
  local var="$1" msg="$2" cur
  cur="$(eval "printf '%s' \"\${$var:-}\"")"
  if [[ -z "$cur" ]]; then
    printf '%s: ' "$msg" >&2
    IFS= read -r cur || { echo "Aborted." >&2; exit 1; }
    export "$var=$cur"
  fi
}
prompt_if_empty AKSBM_EDGE_MACHINE_NAME "Name of the Provisioned SFF EdgeMachine (in the target resource group)"
prompt_if_empty AKSBM_CONTROL_PLANE_IP   "Control plane IP (reserved, same subnet, NOT the host IP)"
# Entra admin group: resolve-or-create instead of prompting for a GUID.
if [[ -z "${AKSBM_ADMIN_GROUP_ID:-}" ]]; then
  echo "Ensuring Entra admin group '${ADMIN_GROUP_NAME}' exists..."
  AKSBM_ADMIN_GROUP_ID="$("$SCRIPT_DIR/ensure-admin-group.sh" --name "$ADMIN_GROUP_NAME" || true)"
  export AKSBM_ADMIN_GROUP_ID
fi
if [[ -z "${AKSBM_SSH_PUBLIC_KEY:-}" ]]; then
  prompt_if_empty AKSBM_SSH_PUBLIC_KEY "SSH public key contents"
fi

# --- Ensure the connectedk8s CLI extension is present ---
ensure_connectedk8s() {
  if ! az extension show --name connectedk8s >/dev/null 2>&1; then
    echo "Installing the connectedk8s CLI extension..."
    az extension add --name connectedk8s >/dev/null
  fi
}

# --- Preflight validation ---
preflight() {
  local failures=0 warnings=0
  echo "Running preflight checks..."

  # 1) Template compiles.
  if az bicep build --file "$TEMPLATE" --stdout >/dev/null 2>&1; then
    echo "  [ok]   main.bicep compiles"
  else
    echo "  [FAIL] main.bicep does not compile: az bicep build --file \"$TEMPLATE\"" >&2
    failures=$((failures + 1))
  fi

  # 2) Region must be eastus (the only supported preview region).
  if [[ "$LOCATION" == "eastus" ]]; then
    echo "  [ok]   region is eastus (preview-supported)"
  else
    echo "  [warn] AKS on bare metal preview is East US only; location='$LOCATION' may fail." >&2
    warnings=$((warnings + 1))
  fi

  # 3) Required inputs present + minimally well-formed.
  if [[ -n "${AKSBM_EDGE_MACHINE_NAME:-}" ]]; then
    echo "  [ok]   edge machine name provided"
  else
    echo "  [FAIL] AKSBM_EDGE_MACHINE_NAME is empty (name of the Provisioned SFF EdgeMachine)." >&2
    failures=$((failures + 1))
  fi
  if [[ "${AKSBM_CONTROL_PLANE_IP:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "  [ok]   control plane IP is a valid IPv4 address"
  else
    echo "  [FAIL] AKSBM_CONTROL_PLANE_IP ('${AKSBM_CONTROL_PLANE_IP:-}') is not a valid IPv4 address." >&2
    failures=$((failures + 1))
  fi
  if [[ "${AKSBM_ADMIN_GROUP_ID:-}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "  [ok]   admin group object ID is a GUID"
  else
    echo "  [FAIL] AKSBM_ADMIN_GROUP_ID ('${AKSBM_ADMIN_GROUP_ID:-}') is not a GUID." >&2
    failures=$((failures + 1))
  fi
  if [[ "${AKSBM_SSH_PUBLIC_KEY:-}" == ssh-* ]]; then
    echo "  [ok]   SSH public key present"
  else
    echo "  [FAIL] AKSBM_SSH_PUBLIC_KEY is empty or not an OpenSSH public key. Use --ssh-key-file." >&2
    failures=$((failures + 1))
  fi

  # 4) Critical resource providers registered (all consumed by the template).
  local crit=(Microsoft.HybridContainerService Microsoft.Kubernetes Microsoft.ExtendedLocation Microsoft.HybridCompute Microsoft.AzureStackHCI Microsoft.KubernetesConfiguration)
  local unreg=() rp st
  for rp in "${crit[@]}"; do
    st=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "Unknown")
    [[ "$st" == "Registered" ]] || unreg+=("$rp ($st)")
  done
  if [[ ${#unreg[@]} -eq 0 ]]; then
    echo "  [ok]   critical resource providers registered"
  else
    echo "  [warn] not registered: ${unreg[*]}" >&2
    echo "         Run scripts/check-providers-sff.sh to register them." >&2
    warnings=$((warnings + 1))
  fi

  # 5) connectedk8s extension present (needed to connect after deploy).
  if az extension show --name connectedk8s >/dev/null 2>&1; then
    echo "  [ok]   connectedk8s CLI extension installed"
  else
    echo "  [warn] connectedk8s CLI extension missing (will be installed)." >&2
    warnings=$((warnings + 1))
  fi

  # 6) Edge machine resolves in the target RG (best-effort; needs Reader on it).
  local em_state
  em_state=$(az resource show -g "$RESOURCE_GROUP" -n "${AKSBM_EDGE_MACHINE_NAME:-}" \
    --resource-type Microsoft.AzureStackHCI/edgeMachines \
    --query "properties.provisioningState" -o tsv 2>/dev/null || echo "")
  if [[ -n "$em_state" ]]; then
    echo "  [ok]   edge machine '${AKSBM_EDGE_MACHINE_NAME}' resolves in $RESOURCE_GROUP (provisioningState=$em_state)"
  else
    echo "  [warn] could not resolve edge machine '${AKSBM_EDGE_MACHINE_NAME:-}' in $RESOURCE_GROUP." >&2
    echo "         The cluster must deploy into the SAME resource group as the Provisioned EdgeMachine (use -g <rg>)." >&2
    warnings=$((warnings + 1))
  fi

  echo
  if (( failures > 0 )); then
    echo "Preflight found $failures blocking issue(s). Fix them, or re-run with --skip-preflight." >&2
    exit 1
  fi
  (( warnings > 0 )) && echo "Preflight passed with $warnings warning(s)." || echo "Preflight passed."
  echo
}

ensure_connectedk8s

echo
echo "Subscription   : $(az account show --query name -o tsv)"
echo "Resource group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo "Template       : $TEMPLATE"
echo

# --- Ensure the resource group exists ---
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group $RESOURCE_GROUP in $LOCATION ..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
  preflight
fi

# --- What-if preview ---
echo "Running what-if preview..."
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS"

if [[ "$WHATIF_ONLY" == "true" ]]; then
  echo "--what-if-only: stopping before deployment."
  exit 0
fi

# --- Confirm before deploying ---
if [[ "$ASSUME_YES" != "true" ]]; then
  printf 'Proceed with the AKS on bare metal deployment? [y/N]: ' >&2
  IFS= read -r reply || reply=""
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "Deploying (typically ~20 minutes)..."
DEPLOY_NAME="aksbm-$(date +%Y%m%d-%H%M%S)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS" \
  --name "$DEPLOY_NAME"

state=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
echo
echo "Deployment '$DEPLOY_NAME' finished: $state"
if [[ "$state" != "Succeeded" ]]; then
  echo "Deployment did not succeed. Inspect: az deployment group show -g $RESOURCE_GROUP -n $DEPLOY_NAME" >&2
  exit 1
fi

CLUSTER_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOY_NAME" \
  --query "properties.outputs.connectedClusterName.value" -o tsv 2>/dev/null || echo "<cluster>")

cat <<EOF

────────────────────────────────────────────────────────────────────
AKS on bare metal cluster '$CLUSTER_NAME' deployed.

Connect to it (run from your LOCAL machine, NOT Cloud Shell):

    $SCRIPT_DIR/connect-aks-baremetal.sh --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP

That installs kubectl + the connectedk8s extension, starts the Arc proxy,
and runs 'kubectl get nodes'. You must be a member of the Entra admin group.

Verify in Azure:  az resource show -g $RESOURCE_GROUP -n $CLUSTER_NAME \\
  --resource-type Microsoft.Kubernetes/connectedClusters --query properties.provisioningState
────────────────────────────────────────────────────────────────────
EOF
