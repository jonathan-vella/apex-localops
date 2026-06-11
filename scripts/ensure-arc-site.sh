#!/usr/bin/env bash
#
# ensure-arc-site.sh - Resolve-or-create the Azure Arc site used by the SFF
# machine-provisioning flow ("Create and configure an Azure Arc site").
#
# Idempotent (mirrors ensure-admin-group.sh): if a site of the given name already exists it
# is reused; otherwise it is created. Pre-creating the site means it is selectable in the
# portal Machine Provisioning > Provision wizard instead of being created by hand.
#
# SCOPE (confirmed against the preview CLI surface):
#   * Arc site     -> az site       (preview ext) -> Microsoft.Edge/sites             [scriptable]
#   * Arc Gateway  -> az arcgateway  (preview ext) -> Microsoft.HybridCompute/gateways [OPTIONAL]
#     The Arc Gateway is NOT required for SFF machine provisioning, so it is OFF by default.
#     Opt in with --with-gateway only if your environment uses one.
#   * The "Configure the site" Region binding and the ownership-voucher upload remain a
#     PORTAL step in the preview (no standalone CLI). provision-machine.sh drives that
#     guided step and waits for 'Provisioned'.
#
# The site name (and gateway id, if created) are printed to STDOUT (so callers can capture
# them); all diagnostics go to STDERR. With --emit it prints `export AKSBM_SITE_NAME=...` lines.
#
# Usage:
#   ./ensure-arc-site.sh                                   # site 'local-sff' in rg-azlocal-sff-eus01
#   ./ensure-arc-site.sh --resource-group rg-azlocal-sff-eus01 -l eastus
#   ./ensure-arc-site.sh --site-name local-sff
#   ./ensure-arc-site.sh --with-gateway --gateway-name localsff-gateway   # also create a gateway
#   ./ensure-arc-site.sh --no-site                         # gateway only (requires --with-gateway)
#   ./ensure-arc-site.sh --emit                            # print `export ...` lines (for eval)
#   ./ensure-arc-site.sh --help
#
# Prerequisites: az login. The arcgateway/site CLI extensions are preview-only and are
# installed automatically with --allow-preview on first use.

set -euo pipefail

RESOURCE_GROUP="rg-azlocal-sff-eus01"
LOCATION="eastus"
SITE_NAME="local-sff"
SITE_DISPLAY_NAME=""
GATEWAY_NAME="localsff-gateway"
# The Arc Gateway is OPTIONAL and not required for SFF machine provisioning -> off by default.
DO_GATEWAY=false
DO_SITE=true
EMIT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g) RESOURCE_GROUP="${2:?missing value}"; shift 2 ;;
    --location|-l) LOCATION="${2:?missing value}"; shift 2 ;;
    --site-name) SITE_NAME="${2:?missing value}"; shift 2 ;;
    --display-name) SITE_DISPLAY_NAME="${2:?missing value}"; shift 2 ;;
    --gateway-name) GATEWAY_NAME="${2:?missing value}"; shift 2 ;;
    --with-gateway) DO_GATEWAY=true; shift ;;
    --no-gateway) DO_GATEWAY=false; shift ;;
    --no-site) DO_SITE=false; shift ;;
    --emit) EMIT=true; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI (az) not found on PATH." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2; exit 1; }

# The arcgateway and site CLI extensions are PREVIEW-only; auto-install grabs stable
# versions and fails ("No suitable stable version"). Install them explicitly with
# --allow-preview so the create/list calls below succeed.
ensure_preview_ext() {
  local ext="$1"
  az extension show --name "$ext" >/dev/null 2>&1 && return 0
  echo "Installing preview CLI extension '$ext'..." >&2
  az extension add --name "$ext" --allow-preview true -y >/dev/null 2>&1 || \
    echo "WARNING: could not install the '$ext' extension; the related step may be skipped." >&2
}
[[ "$DO_GATEWAY" == "true" ]] && ensure_preview_ext arcgateway
[[ "$DO_SITE" == "true" ]] && ensure_preview_ext site

[[ -n "$SITE_DISPLAY_NAME" ]] || SITE_DISPLAY_NAME="$SITE_NAME"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Ensure the resource group exists (the site is RG-scoped).
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group $RESOURCE_GROUP in $LOCATION ..." >&2
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

gateway_id=""
site_id=""

# --- 1. Arc Gateway: resolve-or-create (Microsoft.HybridCompute/gateways) ---
if [[ "$DO_GATEWAY" == "true" ]]; then
  gateway_id=$(az arcgateway list --query "[?name=='${GATEWAY_NAME}'].id | [0]" -o tsv 2>/dev/null || true)
  if [[ -n "$gateway_id" && "$gateway_id" != "None" ]]; then
    echo "Reusing existing Arc Gateway '${GATEWAY_NAME}' (${gateway_id})." >&2
  else
    echo "Creating Arc Gateway '${GATEWAY_NAME}' in ${LOCATION} ..." >&2
    gateway_id=$(az arcgateway create --name "$GATEWAY_NAME" --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" --query id -o tsv 2>/dev/null || true)
    if [[ -z "$gateway_id" || "$gateway_id" == "None" ]]; then
      echo "WARNING: could not create the Arc Gateway. You can create/select one in the portal" >&2
      echo "         during machine provisioning, or re-run with sufficient permissions." >&2
      gateway_id=""
    else
      echo "Created Arc Gateway '${GATEWAY_NAME}' (${gateway_id})." >&2
    fi
  fi
fi

# --- 2. Arc site: resolve-or-create (Microsoft.Edge/sites, RG-scoped) ---
if [[ "$DO_SITE" == "true" ]]; then
  site_id=$(az site list --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" \
    --query "[?name=='${SITE_NAME}'].id | [0]" -o tsv 2>/dev/null || true)
  if [[ -n "$site_id" && "$site_id" != "None" ]]; then
    echo "Reusing existing Arc site '${SITE_NAME}' (${site_id})." >&2
  else
    echo "Creating Arc site '${SITE_NAME}' (resource group scope) ..." >&2
    site_id=$(az site create --site-name "$SITE_NAME" --resource-group "$RESOURCE_GROUP" \
      --subscription "$SUBSCRIPTION_ID" --display-name "$SITE_DISPLAY_NAME" \
      --description "apex-localops SFF site" --query id -o tsv 2>/dev/null || true)
    if [[ -z "$site_id" || "$site_id" == "None" ]]; then
      echo "WARNING: could not create the Arc site. You can create/select one in the portal" >&2
      echo "         during machine provisioning, or re-run with sufficient permissions." >&2
      site_id=""
    else
      echo "Created Arc site '${SITE_NAME}' (${site_id})." >&2
    fi
  fi
fi

# --- 3. Reminder about the residual portal step (preview) ---
cat >&2 <<EOF

Note: in the SFF preview, selecting the site '${SITE_NAME}' and the ownership-voucher
upload are completed in the Azure portal Machine Provisioning > Provision wizard. The
Arc Gateway is optional and not required. The site above is pre-created so you can
simply SELECT it there. provision-machine.sh drives that step and waits for 'Provisioned'.
EOF

# --- 4. Emit results ---
if [[ "$EMIT" == "true" ]]; then
  echo "export AKSBM_SITE_NAME='${SITE_NAME}'"
  [[ -n "$gateway_id" ]] && echo "export AKSBM_ARC_GATEWAY_ID='${gateway_id}'"
  [[ -n "$site_id" ]] && echo "export AKSBM_SITE_ID='${site_id}'"
else
  echo "$SITE_NAME"
fi
