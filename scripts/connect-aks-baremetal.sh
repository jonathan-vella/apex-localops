#!/usr/bin/env bash
#
# connect-aks-baremetal.sh - Connect to an AKS on bare metal (preview) cluster via
# the Azure Arc proxy and run kubectl against it.
#
# The Arc proxy routes kubectl from your machine to the cluster on the SFF device
# without direct network access. You must be a member of the Entra admin group
# specified at cluster deploy time.
#
# Usage:
#   ./connect-aks-baremetal.sh --name <cluster> --resource-group <rg>   # start proxy (foreground)
#   ./connect-aks-baremetal.sh --name <cluster> -g <rg> --get-nodes     # proxy + 'kubectl get nodes' + stop
#   ./connect-aks-baremetal.sh --help
#
# IMPORTANT: Do NOT run this from Azure Cloud Shell (the proxy needs a local MSI
# token audience). Run it from your local machine or the devcontainer.
#
# Prerequisites: az login; the connectedk8s extension (installed if missing);
# kubectl (installed via 'az aks install-cli' if missing).

set -euo pipefail

CLUSTER_NAME=""
# Default to the resource group that holds the cluster (same RG as the EdgeMachine).
RESOURCE_GROUP="rg-localsff"
GET_NODES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name|-n) CLUSTER_NAME="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --get-nodes) GET_NODES=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }
[[ -n "$CLUSTER_NAME" ]] || { echo "ERROR: --name <cluster> is required." >&2; exit 2; }

# --- Ensure tooling: connectedk8s extension + kubectl ---
if ! az extension show --name connectedk8s >/dev/null 2>&1; then
  echo "Installing the connectedk8s CLI extension..."
  az extension add --name connectedk8s >/dev/null
fi
if ! command -v kubectl >/dev/null 2>&1; then
  echo "Installing kubectl via 'az aks install-cli'..."
  az aks install-cli >/dev/null 2>&1 || {
    echo "WARNING: could not auto-install kubectl; install it manually if needed." >&2
  }
fi

if [[ "$GET_NODES" == "true" ]]; then
  # Start the proxy in the background, wait for it to be ready, run kubectl, then stop it.
  echo "Starting the Arc proxy for '$CLUSTER_NAME' (background) ..."
  proxy_log="$(mktemp)"
  az connectedk8s proxy --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" >"$proxy_log" 2>&1 &
  proxy_pid=$!
  trap 'kill "$proxy_pid" >/dev/null 2>&1 || true; rm -f "$proxy_log"' EXIT

  # Wait until the proxy reports it merged the kubeconfig context (up to ~60s).
  for _ in $(seq 1 60); do
    if grep -qiE "Merged|listening on port" "$proxy_log" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$proxy_pid" >/dev/null 2>&1; then
      echo "ERROR: the Arc proxy exited early. Output:" >&2
      cat "$proxy_log" >&2
      exit 1
    fi
    sleep 1
  done

  echo
  echo "Running: kubectl get nodes"
  kubectl get nodes --context "$CLUSTER_NAME" || kubectl get nodes
  echo
  echo "Done. Stopping the proxy."
  exit 0
fi

cat <<EOF
Starting the Azure Arc proxy for cluster '$CLUSTER_NAME' (resource group '$RESOURCE_GROUP').
Keep THIS terminal open. In a SECOND terminal, run:

    kubectl get nodes

Press Ctrl-C here to close the proxy when finished.
EOF
exec az connectedk8s proxy --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP"
