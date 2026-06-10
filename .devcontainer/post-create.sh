#!/usr/bin/env bash
set -euo pipefail

# Named Docker volumes are mounted with root ownership by default. Without this
# fixup the vscode user cannot write Azure CLI state (~/.azure/azureProfile.json)
# or install PowerShell modules (~/.local/share/powershell), which breaks the
# steps below with "Permission denied".
echo "Ensuring mounted volumes are owned by the current user..."
for dir in "$HOME/.azure" "$HOME/.local/share/powershell"; do
  if [[ -d "$dir" && "$(stat -c '%u' "$dir")" != "$(id -u)" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$dir"
  fi
done

echo "Installing or upgrading Bicep CLI..."
az bicep install >/dev/null || az bicep upgrade >/dev/null

echo "Installing Azure PowerShell modules for the vscode user..."
pwsh -NoLogo -NoProfile -NonInteractive -Command '
  $ErrorActionPreference = "Stop"
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
'

echo "Configuring Azure CLI dynamic extension installation..."
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
az config set extension.dynamic_install_allow_preview=false >/dev/null

echo "Tool versions:"
az --version | sed -n '1,3p'
az bicep version
pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString(); (Get-Module -ListAvailable Az.Accounts | Select-Object -First 1 -ExpandProperty Version).ToString()'
azd version
gh --version | sed -n '1p'

if [[ -n "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN is present; gh CLI will use token authentication."
else
  echo "GH_TOKEN is not set. See .devcontainer/README.md for GitHub CLI authentication setup."
fi
