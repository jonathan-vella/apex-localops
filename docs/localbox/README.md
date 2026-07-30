# LocalBox profile — retired

> [!IMPORTANT]
> The **LocalBox** (Arc Jumpstart) profile was **retired in v2.0.0** and removed from `main`.
> Use the **[Self-hosted profile](../selfhosted/overview.md)** instead — it builds the same
> nested three-node Azure Local cluster, clean-room from operator-staged ISOs, with no Arc
> Jumpstart dependency.

## Why it was retired

apex-localops now focuses on two profiles — **Self-hosted** (primary) and **Small Form Factor
(SFF)**. Maintaining the Jumpstart-derived LocalBox build alongside the clean-room self-hosted
build was redundant, so LocalBox was retired.

## Still need LocalBox?

The last release that includes it is
**[v1.3.0](https://github.com/jonathan-vella/apex-localops/releases/tag/v1.3.0)**:

```bash
git checkout v1.3.0
```

## Where to go instead

- **[Self-hosted overview](../selfhosted/overview.md)** ·
  **[quickstart](../selfhosted/quickstart.md)** ·
  **[sizing](../selfhosted/sizing.md)**
- **[Choose a profile](../choose-a-profile.md)**
- **[Documentation home](../README.md)**
