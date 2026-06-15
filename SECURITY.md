# Security policy

apex-localops is a **draft release** under active development. We take security seriously and
appreciate reports that help keep the project and its users safe.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report it privately through GitHub:

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability** (GitHub private vulnerability reporting).
3. Describe the issue, the affected profile or script, and steps to reproduce.

If you cannot use private reporting, contact the maintainer
([@jonathan-vella](https://github.com/jonathan-vella)) and ask for a private channel before
sharing details.

Please include:

- The affected area (profile, script, Bicep template, or workflow).
- A description of the impact and how to reproduce it.
- Any proof-of-concept, logs, or configuration — with **all secrets redacted**.

We will acknowledge your report, investigate, and keep you updated on a fix. Because this is a
pre-1.0 project maintained on a best-effort basis, response times may vary; we will do our best
to respond promptly.

## Scope

This repository deploys nested Azure Local evaluation environments. Security-relevant areas
include the Bicep templates under [infra/bicep/](infra/bicep/), the deployment scripts under
[scripts/](scripts/), and the in-VM automation under [artifacts/](artifacts/).

Out of scope:

- **Vendored, read-only content** — `docs/upstream/**`, `docs/azure-local-sff/upstream/**`, and
  `artifacts/sff/vendor/**`. Report issues in those upstream to their source projects (see
  [ATTRIBUTION.md](ATTRIBUTION.md)).
- **Microsoft Azure services and Azure Local itself** — report those through
  [Microsoft's security channels](https://www.microsoft.com/msrc).
- The **preview** nature of SFF and AKS on bare metal: these run on preview Azure APIs and are
  for evaluation only, not production.

## How this project handles secrets

By design, the deployment flow keeps secrets out of the repository:

- Windows admin passwords are read from environment variables at deploy time and are **never**
  committed or written to disk by the scripts.
- In-VM automation authenticates to Azure with **managed identities**, not stored credentials.
- Tenant-specific identifiers are resolved at runtime, not baked into committed parameters.

If you find a case where a secret could be exposed, committed, or logged, please report it using
the private process above.
