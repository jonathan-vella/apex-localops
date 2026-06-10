# Development Container for apex-localops

This devcontainer provides a lean, repeatable workstation for deploying and operating this repository's Azure Local sandbox. It is intended to work from VS Code on Windows, Linux, and macOS hosts, on both x86_64 and arm64 processors.

Base image: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`

`ubuntu-24.04` is the newest Ubuntu tag currently published for `mcr.microsoft.com/devcontainers/base`. The Microsoft devcontainer base image and the selected features publish multi-architecture Linux images for amd64 and arm64.

## Included Tools

Devcontainer features install the latest available versions of:

| Tool | Purpose |
| --- | --- |
| Azure CLI | Azure deployment and resource operations |
| Bicep CLI | ARM/Bicep template build and lint through `az bicep` |
| Azure PowerShell | PowerShell-based Azure administration with the `Az` module |
| Azure Developer CLI (`azd`) | Azure developer workflow support |
| GitHub CLI | Repository, issue, pull request, and workflow operations |

The post-create step also installs common shell utilities, configures Azure CLI extension auto-install, installs the latest `Az` PowerShell module for the `vscode` user, and verifies tool versions.

## Quick Start

1. Install Docker Desktop or another VS Code Dev Containers-compatible container runtime.
2. Install the VS Code Dev Containers extension: `ms-vscode-remote.remote-containers`.
3. Open this repository in VS Code.
4. Run `Dev Containers: Reopen in Container` from the Command Palette.
5. Authenticate when the container opens:

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## GitHub CLI Authentication (`GH_TOKEN`)

HTTPS-based `gh auth login` can fail inside devcontainers on some host/platform combinations. The supported approach for this repository is a Personal Access Token (PAT) exposed as `GH_TOKEN` through VS Code settings. The container reads it automatically with this entry in `devcontainer.json`:

```json
"GH_TOKEN": "${localEnv:GH_TOKEN}"
```

Do not commit tokens to this repository.

### Step 1: Create a Fine-Grained PAT

Fine-grained PATs work with the GitHub CLI through `GH_TOKEN`.

1. Go to GitHub -> Settings -> Developer settings -> Personal access tokens -> Fine-grained tokens.
2. Generate a new token.
3. Set an expiry, such as 90 days, and rotate it before expiry.
4. Choose repository access for this repository, or all repositories if that matches your workflow.
5. Grant the minimum permissions needed for local repository operations:

| Permission | Access |
| --- | --- |
| Contents | Read/Write |
| Metadata | Read |
| Pull requests | Read/Write |
| Issues | Read/Write |
| Workflows | Read/Write |

6. Copy the token value.

### Step 2: Add `GH_TOKEN` to VS Code User Settings

Open VS Code settings JSON and add the entry for your host OS. Replace the placeholder with your token.

Windows:

```json
"terminal.integrated.env.windows": {
  "GH_TOKEN": "github_pat_your_token_here"
}
```

Linux:

```json
"terminal.integrated.env.linux": {
  "GH_TOKEN": "github_pat_your_token_here"
}
```

macOS:

```json
"terminal.integrated.env.osx": {
  "GH_TOKEN": "github_pat_your_token_here"
}
```

Save the settings file, restart VS Code if needed, then rebuild the container with `Dev Containers: Rebuild Container`.

### Step 3: Verify Inside the Container

```bash
gh auth status
```

Expected result:

```text
Logged in to github.com as <your-username>
```

When the PAT expires, update the value in VS Code settings and rebuild the container.

## Notes

- Azure CLI credentials are stored in a named Docker volume: `apex-localops-azure`.
- PowerShell modules are stored in a named Docker volume: `apex-localops-powershell`.
- Run `az bicep upgrade` inside the container if you need to force a Bicep update between rebuilds.
- Rebuild without cache when you want to pull the newest base image and feature layers.
