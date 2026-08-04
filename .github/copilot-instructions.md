# Copilot instructions for this repository

This is a teaching repo for an Azure Infrastructure-as-Code workshop. Learners
read every diff you produce, so favour clarity over cleverness and explain
*why* a change is shaped the way it is.

## Bicep

- **Use Azure Verified Modules.** Prefer `br/public:avm/res/...` over raw
  `Microsoft.*` resources. Raw resources are acceptable only where no AVM module
  exists — currently the two in `labs/modules/`.
- **Pin every module version** (`avm/res/network/virtual-network:0.9.0`). Never
  use a floating tag. Reproducibility is one of the things the workshop teaches.
- **Deploy at resource-group scope.** Every template targets a *pre-existing*
  resource group and must not create one. `targetScope` stays at its default.
- **`prefix` is `@maxLength(12)`** and lowercase. It prefixes every resource
  name; some Azure resource types have short name limits.
- Mark every password or key `@secure()`. Never give a secure parameter a
  default value, and never emit one as an output — `bicepconfig.json` treats
  both as errors.
- Parameter files read the environment:
  `readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')`. That single mechanism is
  what lets the local CLI, GitHub Actions and Copilot paths share one template.
  Keep it.
- Follow the region default `eastus2`. `no-hardcoded-location` is deliberately
  off in `bicepconfig.json` — the labs hardcode a default on purpose.

## Before saying a change is done

Always, in this order:

```powershell
az bicep build --file <template>.bicep --stdout > $null
az deployment group what-if --resource-group $env:AZURE_RESOURCE_GROUP --parameters <template>.bicepparam
```

Compile first, then show the what-if diff and **stop**, unless you were
explicitly asked to deploy. Deployments cost real money — Azure Firewall alone
is $1.25/hr.

## The labs build on each other

| Lab | Creates | Depends on |
|---|---|---|
| L1 | Hub + spoke1 VNets, Bastion, one VM | nothing |
| L2 | Firewall in L1's hub, web subnet in L1's spoke, route tables on **both** spoke subnets | L1 |
| L3 | A **new** spoke2, peered to L1's hub — Container Apps, SQL, Key Vault | L1 only, **not** L2 |
| L4 | Second region, SQL failover group, Front Door | L3 |

L3 does not reuse L1's spoke and does not route through L2's firewall. Do not
describe it as building on L2.

## Scripts

- PowerShell, not bash, for anything run on a lab machine — `.ps1` files are
  pinned to CRLF in `.gitattributes`, while YAML and shell must stay LF because
  they run on Linux runners.
- Match the existing conventions in `scripts/`: `Write-Ok` / `Write-Fail` /
  `Write-Info` helpers, `[CmdletBinding()]`, and `-WhatIf` on anything
  destructive. Instructors are trained to run `-WhatIf` first.
- Validate everything before changing anything, so a partial failure cannot
  leave a half-configured state.

## Workflows

- All deploys are `workflow_dispatch` only. Nothing deploys on push.
- Azure auth is OIDC. There is no client secret in this repo and there must
  never be one.
- Keep `permissions:` minimal — `id-token: write` and `contents: read`.

## Documentation

`docs/wiki/` is a mirror of the GitHub Wiki and is published from here. It is
validated by `scripts/Publish-Wiki.ps1`, which runs on every pull request, so
match the existing page structure: one H1 per page, absolute links, GitHub
alerts rather than emoji blockquotes, and a `<details>` text description after
every mermaid diagram. Run `./scripts/Publish-Wiki.ps1 -CheckOnly -Strict`
before proposing wiki changes.
