#!/usr/bin/env bash
#
# deploy-aks-sample-app.sh - Deploy (or remove) a sample nginx workload on an AKS on
# bare metal (preview) cluster and print how to reach it.
#
# Mirrors the Microsoft Learn walkthrough (aks-bare-metal-deploy-application): it
# starts the Azure Arc proxy, applies a NodePort Deployment+Service from a manifest,
# waits for the rollout, then prints the NodePort and access URL.
#
# Single-node preview notes baked into the manifest (artifacts/aks/sample-app/hello-app.yaml):
#   * NodePort only (LoadBalancer is NOT supported in the preview).
#   * MCR image (mcr.microsoft.com) — the registry guaranteed reachable from the device.
#   * Resource requests/limits so the app cannot starve the control plane.
#
# Usage:
#   ./deploy-aks-sample-app.sh                                  # deploy to localsff-aks in rg-sff-azl-eus01
#   ./deploy-aks-sample-app.sh --name <cluster> -g <rg>         # target a specific cluster
#   ./deploy-aks-sample-app.sh --host-ip 192.168.200.50         # print the full access URL
#   ./deploy-aks-sample-app.sh --manifest <path>                # use a different manifest
#   ./deploy-aks-sample-app.sh --port 47051                     # if the default proxy port is busy
#   ./deploy-aks-sample-app.sh --delete                         # remove the sample app
#   ./deploy-aks-sample-app.sh --help
#
# IMPORTANT: Do NOT run from Azure Cloud Shell (the proxy needs a local MSI token
# audience). Run from your local machine or the devcontainer.
#
# Prerequisites: az login; the connectedk8s extension (installed if missing);
# kubectl (installed via 'az aks install-cli' if missing); a Succeeded cluster.

set -euo pipefail

CLUSTER_NAME="localsff-aks"
RESOURCE_GROUP="rg-sff-azl-eus01"
APP_NAME="hello-app"
HOST_IP=""
PROXY_PORT=""
DELETE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFEST="$REPO_ROOT/artifacts/aks/sample-app/hello-app.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name|-n) CLUSTER_NAME="${2:?missing value}"; shift 2 ;;
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --manifest) MANIFEST="${2:?missing value}"; shift 2 ;;
    --app-name) APP_NAME="${2:?missing value}"; shift 2 ;;
    --host-ip) HOST_IP="${2:?missing value}"; shift 2 ;;
    --port) PROXY_PORT="${2:?missing value}"; shift 2 ;;
    --delete) DELETE=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "ERROR: manifest not found: $MANIFEST" >&2; exit 1; }

# --- Ensure tooling: connectedk8s extension + kubectl ---
if ! az extension show --name connectedk8s >/dev/null 2>&1; then
  echo "Installing the connectedk8s CLI extension..."
  az extension add --name connectedk8s >/dev/null
fi
if ! command -v kubectl >/dev/null 2>&1; then
  # az aks install-cli defaults to a root-owned location, which a dev-container user cannot write.
  echo "Installing kubectl into $HOME/bin ..."
  mkdir -p "$HOME/bin"
  az aks install-cli --install-location "$HOME/bin/kubectl" \
    --kubelogin-install-location "$HOME/bin/kubelogin" >/dev/null 2>&1 || {
    echo "ERROR: could not auto-install kubectl; install it manually and re-run." >&2
    exit 1
  }
  export PATH="$HOME/bin:$PATH"
fi

# --- Start the Arc proxy in the background and wait until it is ready ---
echo "Starting the Arc proxy for '$CLUSTER_NAME' (background) ..."
proxy_log="$(mktemp)"
kubecfg="$(mktemp)"
proxy_args=(--name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --file "$kubecfg")
[[ -n "$PROXY_PORT" ]] && proxy_args+=(--port "$PROXY_PORT")
az connectedk8s proxy "${proxy_args[@]}" >"$proxy_log" 2>&1 &
proxy_pid=$!
cleanup_proxy() {
  # Killing only the parent leaves the arcProxy child holding the port, which blocks the next run.
  if [[ -n "${proxy_pid:-}" ]]; then
    pkill -P "$proxy_pid" >/dev/null 2>&1 || true
    kill "$proxy_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$proxy_log" "$kubecfg"
}
trap cleanup_proxy EXIT

# The proxy prints nothing once its output is redirected, so prove readiness with a real API
# call through the generated kubeconfig instead of scraping its log for a banner.
ready=false
for _ in $(seq 1 60); do
  if kubectl --kubeconfig "$kubecfg" version 2>/dev/null | grep -q 'Server Version'; then
    ready=true
    break
  fi
  if ! kill -0 "$proxy_pid" >/dev/null 2>&1; then
    echo "ERROR: the Arc proxy exited early. Output:" >&2
    cat "$proxy_log" >&2
    exit 1
  fi
  sleep 2
done
if [[ "$ready" != "true" ]]; then
  echo "ERROR: timed out waiting for the Arc proxy to become ready. Output:" >&2
  cat "$proxy_log" >&2
  exit 1
fi

kc() {
  kubectl --kubeconfig "$kubecfg" "$@"
}

# --- Delete path ---
if [[ "$DELETE" == "true" ]]; then
  echo "Removing the sample app from '$CLUSTER_NAME' ..."
  kc delete -f "$MANIFEST" --ignore-not-found
  echo "Done."
  exit 0
fi

# --- Apply the manifest and wait for the rollout ---
echo "Applying $MANIFEST ..."
kc apply -f "$MANIFEST"

echo "Waiting for the '$APP_NAME' deployment to become available (up to 5 min) ..."
if ! kc rollout status "deployment/$APP_NAME" --timeout=300s; then
  # The proxied kubeconfig is deleted on exit, so surface the diagnosis now rather than
  # pointing at a kubectl command the operator can no longer run.
  echo "ERROR: rollout did not complete in time." >&2
  kc get pods -l "app=$APP_NAME" -o wide >&2 || true
  kc describe pod -l "app=$APP_NAME" 2>/dev/null | sed -n '/Events:/,$p' >&2 || true
  exit 1
fi

# --- Resolve the NodePort ---
node_port="$(kc get svc "$APP_NAME" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)"
if [[ -z "$node_port" ]]; then
  echo "WARNING: could not read the NodePort. Check: kubectl --context $CLUSTER_NAME get svc $APP_NAME" >&2
  exit 1
fi

# --- Resolve the host IP for the URL (best effort) ---
if [[ -z "$HOST_IP" ]]; then
  HOST_IP="$(az resource list -g "$RESOURCE_GROUP" \
    --resource-type 'Microsoft.AzureStackHCI/edgeMachines' \
    --query "[0].properties.ipAddress" -o tsv 2>/dev/null || true)"
fi

echo
echo "────────────────────────────────────────────────────────────────────"
echo "Sample app '$APP_NAME' is running on '$CLUSTER_NAME'."
echo "  Service type : NodePort"
echo "  NodePort     : $node_port"
if [[ -n "$HOST_IP" && "$HOST_IP" != "None" ]]; then
  echo "  Access URL   : http://$HOST_IP:$node_port"
else
  echo "  Access URL   : http://<bare-metal-host-ip>:$node_port"
  echo "               (pass --host-ip <ip> to print the full URL)"
fi
echo
echo "Reach it from a machine on the device's network. Remove it later with:"
echo "  $SCRIPT_DIR/deploy-aks-sample-app.sh --delete --name $CLUSTER_NAME -g $RESOURCE_GROUP"
echo "────────────────────────────────────────────────────────────────────"
