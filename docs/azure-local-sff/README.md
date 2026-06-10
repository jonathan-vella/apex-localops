# Azure Local SFF — vendored upstream documentation

The [`upstream/`](upstream/) folder is a **read-only mirror** of the
`azure-local/small-form-factor` documentation from
[`MicrosoftDocs/azure-stack-docs`](https://github.com/MicrosoftDocs/azure-stack-docs),
vendored so this repo's SFF guidance works offline and is pinned to a known revision.

> [!IMPORTANT]
> Do **not** edit files under `upstream/` — they are overwritten on every sync. The mirror
> is refreshed by [.github/workflows/sync-azure-local-sff-docs.yml](../../.github/workflows/sync-azure-local-sff-docs.yml)
> (weekly + on demand) via a blobless sparse checkout of just the `small-form-factor` folder.

## Canonical sources (Microsoft Learn)

| Topic | Learn URL |
| --- | --- |
| Overview | <https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-overview> |
| Subscription setup | <https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-subscription-setup> |
| Test in a Hyper-V VM | <https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-vm-installation> |
| Connect from the portal | <https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-connect-portal> |
| Troubleshoot | <https://learn.microsoft.com/azure/azure-local/small-form-factor/small-form-factor-troubleshoot> |

## How this repo uses it

- [docs/sff-quickstart.md](../sff-quickstart.md) — deploy + stage + monitor.
- [docs/sff-runbook.md](../sff-runbook.md) — voucher + portal machine provisioning.
- [docs/sff-sizing.md](../sff-sizing.md) — sizing and cost.

## License & attribution

The vendored docs are © Microsoft and licensed **CC BY 4.0** (compatible with this repo's
[LICENSE](../../LICENSE)). See [ATTRIBUTION.md](../../ATTRIBUTION.md) for the credit and the
pinned upstream commit.
