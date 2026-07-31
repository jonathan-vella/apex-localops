#!/usr/bin/env bash
#
# check-providers-sff.sh - Ensure the Azure resource providers and preview feature
# required by Azure Local Small Form Factor (SFF) machine provisioning are
# registered in the active subscription.
#
# Usage:
#   ./check-providers-sff.sh                      # check + register missing, then poll
#   ./check-providers-sff.sh --check-only         # report status only, make no changes
#   ./check-providers-sff.sh --subscription <id>  # target a specific subscription
#   ./check-providers-sff.sh --help
#
# Safe to re-run: provider/feature registration is idempotent.
#
# Prerequisites: az login. SFF is a PREVIEW feature; the AzureLocalZTP feature on
# Microsoft.DeviceOnboarding gates zero-touch machine provisioning.

set -euo pipefail

# Resource providers required by Azure Local SFF (per the subscription-setup guide).
REQUIRED_PROVIDERS=(
  Microsoft.Edge
  Microsoft.AzureStackHCI
  Microsoft.HybridCompute
  Microsoft.GuestConfiguration
  Microsoft.HybridConnectivity
  Microsoft.KeyVault
  Microsoft.Storage
  Microsoft.Kubernetes
  Microsoft.KubernetesConfiguration
  Microsoft.ExtendedLocation
  Microsoft.HybridContainerService
  Microsoft.DeviceOnboarding
  Microsoft.Insights
)

# Preview feature flag: zero-touch provisioning (ZTP) for SFF machine provisioning.
FEATURE_NAMESPACE="Microsoft.DeviceOnboarding"
FEATURE_NAME="AzureLocalZTP"

CHECK_ONLY=false
SUBSCRIPTION=""
POLL_TIMEOUT_SECONDS=900
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

# 1) Report current provider state; collect providers that are not yet Registered.
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

# 2) Report the AzureLocalZTP preview feature state.
feature_state=$(az feature show --namespace "$FEATURE_NAMESPACE" --name "$FEATURE_NAME" \
  --query "properties.state" -o tsv 2>/dev/null || echo "NotRegistered")
echo "Preview feature ${FEATURE_NAMESPACE}/${FEATURE_NAME}: ${feature_state}"
echo

if [[ "$CHECK_ONLY" == "true" ]]; then
  if [[ ${#to_register[@]} -eq 0 && "$feature_state" == "Registered" ]]; then
    echo "All required providers and the AzureLocalZTP feature are registered."
  else
    echo "(--check-only) Some providers/feature are not registered. Re-run without --check-only to register."
  fi
else
  # 3) Register the AzureLocalZTP feature first (provider registration must follow it
  #    to propagate the feature into the provider).
  if [[ "$feature_state" != "Registered" ]]; then
    echo "Registering preview feature ${FEATURE_NAMESPACE}/${FEATURE_NAME} ..."
    az feature register --namespace "$FEATURE_NAMESPACE" --name "$FEATURE_NAME" >/dev/null

    echo "Waiting for feature registration to complete (can take several minutes)..."
    deadline=$(( $(date +%s) + POLL_TIMEOUT_SECONDS ))
    while true; do
      feature_state=$(az feature show --namespace "$FEATURE_NAMESPACE" --name "$FEATURE_NAME" \
        --query "properties.state" -o tsv 2>/dev/null || echo "NotRegistered")
      [[ "$feature_state" == "Registered" ]] && { echo "Feature ${FEATURE_NAME} is now Registered."; break; }
      if [[ $(date +%s) -ge $deadline ]]; then
        echo "WARNING: Timed out waiting for feature ${FEATURE_NAME} (state: ${feature_state})." >&2
        echo "Re-run this script to continue polling." >&2
        break
      fi
      sleep "$POLL_INTERVAL_SECONDS"
    done
    # Propagate the feature into its provider namespace.
    az provider register --namespace "$FEATURE_NAMESPACE" >/dev/null || true
  fi

  # 4) Register only the missing providers.
  if [[ ${#to_register[@]} -gt 0 ]]; then
    for rp in "${to_register[@]}"; do
      echo "Registering ${rp} ..."
      az provider register --namespace "$rp" >/dev/null
    done

    echo "Waiting for provider registration to complete (can take several minutes)..."
    deadline=$(( $(date +%s) + POLL_TIMEOUT_SECONDS ))
    while true; do
      pending=()
      for rp in "${to_register[@]}"; do
        state=$(az provider show --namespace "$rp" --query registrationState -o tsv 2>/dev/null || echo "NotFound")
        [[ "$state" != "Registered" ]] && pending+=("$rp")
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
  else
    echo "All required providers are already registered."
  fi
fi
echo

# 5) Manual reminders the SFF preview requires but that this script cannot automate.
cat <<'EOF'
Manual setup the SFF preview also requires (cannot be automated here):
  * RBAC: confirm you have Owner (or Contributor + Role Based Access Control
    Administrator) on the target subscription/resource group, Active and Permanent.
  * Microsoft Entra ID security group: create or identify a group of machine
    operators (used during portal machine provisioning to authorize access).
See: https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-subscription-setup
EOF
