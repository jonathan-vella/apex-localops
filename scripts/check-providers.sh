#!/usr/bin/env bash
#
# check-providers.sh - Ensure the Azure resource providers required by Jumpstart
# LocalBox are registered in the active subscription, then print the
# Microsoft.AzureStackHCI resource-provider object id (spnProviderId) that
# main.bicepparam needs.
#
# Usage:
#   ./check-providers.sh                      # check + register missing, then poll
#   ./check-providers.sh --check-only         # report status only, make no changes
#   ./check-providers.sh --subscription <id>  # target a specific subscription
#   ./check-providers.sh --help
#
# Safe to re-run: provider registration is idempotent.

set -euo pipefail

# Resource providers required by LocalBox (per the official deployment guide).
REQUIRED_PROVIDERS=(
  Microsoft.HybridCompute
  Microsoft.GuestConfiguration
  Microsoft.HybridConnectivity
  Microsoft.AzureStackHCI
  Microsoft.Kubernetes
  Microsoft.KubernetesConfiguration
  Microsoft.ExtendedLocation
  Microsoft.ResourceConnector
  Microsoft.HybridContainerService
  Microsoft.Attestation
  Microsoft.Storage
  Microsoft.Insights
  Microsoft.KeyVault
  Microsoft.EdgeMarketplace
)

CHECK_ONLY=false
SUBSCRIPTION=""
POLL_TIMEOUT_SECONDS=600
POLL_INTERVAL_SECONDS=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=true; shift ;;
    --subscription) SUBSCRIPTION="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2
  exit 1
fi

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi

sub_name=$(az account show --query name -o tsv)
sub_id=$(az account show --query id -o tsv)
echo "Subscription: ${sub_name} (${sub_id})"
echo

# 1) Report current state; collect providers that are not yet Registered.
to_register=()
printf '%-42s %s\n' "PROVIDER" "STATE"
printf '%-42s %s\n' "------------------------------------------" "----------"
for rp in "${REQUIRED_PROVIDERS[@]}"; do
  state=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "NotFound")
  printf '%-42s %s\n' "$rp" "$state"
  if [[ "$state" != "Registered" ]]; then
    to_register+=("$rp")
  fi
done
echo

if [[ ${#to_register[@]} -eq 0 ]]; then
  echo "All required providers are already registered."
else
  echo "Not registered: ${to_register[*]}"
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "(--check-only) Skipping registration."
  else
    # 2) Register only the missing providers.
    for rp in "${to_register[@]}"; do
      echo "Registering ${rp} ..."
      az provider register --namespace "$rp" >/dev/null
    done

    # 3) Poll until everything is Registered (or timeout).
    echo "Waiting for registration to complete (can take several minutes)..."
    deadline=$(( $(date +%s) + POLL_TIMEOUT_SECONDS ))
    while true; do
      pending=()
      for rp in "${to_register[@]}"; do
        state=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$state" != "Registered" ]]; then
          pending+=("$rp")
        fi
      done
      if [[ ${#pending[@]} -eq 0 ]]; then
        echo "All required providers are now registered."
        break
      fi
      if [[ $(date +%s) -ge $deadline ]]; then
        echo "WARNING: Timed out waiting for: ${pending[*]}" >&2
        echo "Re-run this script to continue polling." >&2
        break
      fi
      sleep "$POLL_INTERVAL_SECONDS"
    done
  fi
fi
echo

# 4) Resolve and print spnProviderId for main.bicepparam.
echo "Resolving Microsoft.AzureStackHCI resource provider object id (spnProviderId)..."
spn=$(az ad sp list --display-name "Microsoft.AzureStackHCI Resource Provider" --query "[0].id" -o tsv 2>/dev/null || true)
if [[ -n "${spn:-}" ]]; then
  echo
  echo "  spnProviderId = ${spn}"
  echo
  echo "Paste that value into main.bicepparam (param spnProviderId)."
else
  echo "spnProviderId not available yet." >&2
  echo "If Microsoft.AzureStackHCI was just registered, wait ~1 minute and re-run, or run:" >&2
  echo "  az ad sp list --display-name \"Microsoft.AzureStackHCI Resource Provider\" --query \"[0].id\" -o tsv" >&2
fi
