# IaC Demo — Bicep + GitHub Copilot + GitHub Actions → Azure

Learn to author **Azure Bicep** infrastructure-as-code with **GitHub Copilot agent mode in VS Code**, built entirely from **Azure Verified Modules (AVM)**, and deploy it to Azure with **GitHub Actions (OIDC)** — no stored cloud credentials.

> [!IMPORTANT]
> **Windows 11 only.** The setup and helper scripts target Windows 11 — they use `winget` to install the toolchain and the Windows user environment store to save settings. macOS and Linux are **not supported today**: `Install-LabTools.ps1` will not run, and `Load-LabSettings.ps1 -Persist` silently saves nothing. Everything *after* setup — the Bicep templates, the GitHub Actions workflows, Azure itself — is platform-agnostic; it is the on-ramp that is Windows-bound.

The demo is four **cumulative lab stages**. Each stage builds on the infrastructure the previous one deployed, and each gives you 2–3 ways to test what you built:

| Stage | What you build | What it adds | Tests |
|-------|----------------|--------------|-------|
| **[L1.1 — Core Deployment](../../wiki/Curriculum-L1-1-Core-Deployment)** | Hub + spoke VNets (peered), Bastion, 1 Linux VM | Core networking & connectivity | Bastion SSH, cross-peering curl/ping, peering state check |
| **[L1.2 — Architecture Expansion](../../wiki/Curriculum-L1-2-Architecture-Expansion)** | 3 nginx VMs behind an internal LB, Azure Firewall (DNAT + egress control), NSGs, route tables | Traffic inspection & load balancing | Round-robin curl via firewall, blocked vs allowed egress, NSG flow verify |
| **[L1.3 — Multi-Service Application](../../wiki/Curriculum-L1-3-Multi-Service-Application)** | Azure Container Apps, Azure SQL, Key Vault, managed identity, monitoring + alerting | Containers, data tier, **private networking** (private endpoints, no public data plane) | Hit the app URL, prove SQL is private-only, trigger an alert |
| **[L1.4 — Production-Ready Platform](../../wiki/Curriculum-L1-4-Production-Platform)** | Second region, SQL failover group, Azure Front Door | Multi-region HA & global entry point | Front Door URL, simulated regional failover, SQL failover group |

> 📖 **The full workshop guide lives in the [Wiki](../../wiki).**
> - Brand new to any of this? Start with the **[Start-Here Checklist](../../wiki/Start-Here-Checklist)** and **[Understanding IaC](../../wiki/Understanding-IaC)**.
> - New to GitHub itself (repos, Actions, secrets vs. variables)? **[GitHub Essentials](../../wiki/GitHub-Essentials)**.
> - Want to get comfortable with VS Code, Bicep, and Copilot first? **[Getting Comfortable with the Tools](../../wiki/Getting-Comfortable-with-the-Tools)**.
>
> 🧭 **There is more after L4.** These four labs are *Level 1* of a six-level path that follows an Azure environment's operational lifecycle — deploy, monitor, secure, protect, detect, recover. Eighteen chapters with templates and workflows live in [`curriculum/`](curriculum/), none of which change anything above: **[Curriculum Redesign](../../wiki/Curriculum-Redesign)**.

---

## 1. Install the software

Everything installs on **Windows 11** via `winget`, or from the download links if `winget` is unavailable. macOS and Linux are not supported — see the note at the top.

No execution-policy bypass command is required for this lab setup.

Recommended one-shot path on Windows (run in an elevated PowerShell window):

```powershell
./scripts/Install-LabTools.ps1
```

| Tool | Why you need it | winget | Download |
|------|-----------------|--------|----------|
| **Visual Studio Code** | Editor + Copilot agent mode home | `winget install Microsoft.VisualStudioCode` | [code.visualstudio.com](https://code.visualstudio.com/download) |
| **GitHub Copilot** (VS Code extensions) | The AI agent that writes your Bicep | — (install in VS Code: *GitHub Copilot* + *GitHub Copilot Chat*) | [marketplace](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) |
| **Bicep** (VS Code extension) | Bicep language server, validation, AVM IntelliSense | — (install in VS Code: *Bicep*) | [marketplace](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep) |
| **Git** | Version control | `winget install Git.Git` | [git-scm.com](https://git-scm.com/downloads) |
| **GitHub Desktop** | Easy clone/commit/push UI | `winget install GitHub.GitHubDesktop` | [desktop.github.com](https://desktop.github.com/) |
| **GitHub CLI** (`gh`) | Repo secrets, workflow runs from the terminal | `winget install GitHub.cli` | [cli.github.com](https://cli.github.com/) |
| **Azure CLI** (`az`) | Deployments, what-if, testing — Copilot agent mode drives this | `winget install Microsoft.AzureCLI` | [learn.microsoft.com/cli/azure](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| **Bicep CLI** | Compiles/lints the templates | `az bicep install` (after Azure CLI) | [docs](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) |
| PowerShell 7 *(optional)* | Modern shell for Windows | `winget install Microsoft.PowerShell` | [github.com/PowerShell](https://github.com/PowerShell/PowerShell/releases) |

Verify your install:

```bash
git --version
gh --version
az --version
az bicep version
```

This repo recommends the right VS Code extensions automatically — accept the prompt when you first open the folder (see [.vscode/extensions.json](.vscode/extensions.json)).

> 🧭 Deeper install/config guidance for every tool: **[Wiki → Tools and References](../../wiki/Tools-and-References)**.

## 2. Get the code

1. Download and run `Connect-AzureAndGitHub.ps1` to auto-fork and clone:
   ```powershell
   Invoke-WebRequest "https://raw.githubusercontent.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/main/scripts/Connect-AzureAndGitHub.ps1" -OutFile .\Connect-AzureAndGitHub.ps1
   .\Connect-AzureAndGitHub.ps1
   ```
2. Open the cloned folder in **VS Code** and sign in to Copilot when prompted.

## 3. Sign in to everything

```bash
az login                 # Azure
gh auth login            # GitHub CLI
```

You need an Azure subscription where you can create resource groups, and a GitHub Copilot subscription (Free tier works).

## 4. Wire up GitHub → Azure (OIDC, one-time)

GitHub Actions logs into Azure with a **federated credential** — nothing but non-secret IDs are stored, and there is no cloud password to leak. One script sets up the entire handshake, auto-detecting your fork from the tools you're already signed in to.

> **Classroom participants:** your instructor has pre-created a resource group for you (e.g. `rg-techdemo-<yourname>`) and granted you Contributor on it. Use `-ResourceGroup` and `-Prefix` so the script scopes access correctly and avoids name conflicts with other participants.

> **Self-hosted:** `-ResourceGroup` is required for you too, and no lab creates the group. Make it first with `az group create --name "rg-techdemo-<yourname>" --location eastus2`.

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-techdemo-<yourname>" -Prefix "<yourname>" -WhatIf   # preview — changes nothing
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-techdemo-<yourname>" -Prefix "<yourname>"
```

`-ResourceGroup` is required on **every** run, `-WhatIf` included, because deploy workflows expect the `AZURE_RESOURCE_GROUP` secret — the preview asks for it so it can't report a plan the real run would reject.

This creates the Entra app + service principal, adds a federated credential for your fork's branch, grants Contributor on your assigned resource group, and pushes all the required repo secrets and variables (including strong throwaway VM/SQL passwords it generates for you). Re-running rewrites the identity and resource-group secrets so they always match the app and group just configured, and leaves existing VM/SQL passwords alone so they stay in step with anything already deployed.

**Secrets set:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`  
**Variables set:** `AZURE_PREFIX` (your unique prefix), `AZURE_LOCATION` (defaults to `eastus2`)

After setup succeeds, trigger **Curriculum L1.1 - Core Deployment** in GitHub Actions (`Actions` tab -> select workflow -> `Run workflow`).

> Want to understand each step rather than run one script? The manual `az`/`gh` walkthrough is in **[Wiki → Deployment Guide](../../wiki/Deployment-Guide)**. New to secrets vs. variables? See **[Wiki → GitHub Essentials](../../wiki/GitHub-Essentials)**.

## 5. Start the workshop

Head to the **[Wiki Home](../../wiki)** and begin with **L1.1**. Each lab guide shows you the Copilot agent-mode prompts to author/modify the Bicep, the workflow to deploy it, and the tests to prove it works.

## Repo map

```
curriculum/
  L1.1-core-deployment/            hub+spoke, Bastion, test VM
  L1.2-architecture-expansion/     internal LB + 3 web VMs + Azure Firewall
  L1.3-multi-service-application/  Container Apps, SQL, Key Vault, monitoring, private endpoints
  L1.4-production-platform/        second region, SQL failover group, Front Door
  L2.1 ... L6.3/                   18 chapters: monitor, secure, protect, detect, recover
  modules/                         the only two non-AVM modules (subnet-on-existing-VNet, failover group)
scripts/
  Connect-AzureAndGitHub.ps1  auto-fork + clone helper (sets upstream remote)
  Setup-Oidc.ps1    one-command GitHub↔Azure OIDC handshake (+ repo secrets)
  Cleanup-Labs.ps1  tear down lab resources (and optionally the OIDC identity)
.github/workflows/  curriculum-l1-1..l1-4 + curriculum-l2..l6 + teardown.yml (all OIDC, manual dispatch)
unit cost/
  Build-CostDocs.ps1  regenerates both cost handouts from one unit-rate table
bicepconfig.json    linter settings
```

All Azure resources come from [Azure Verified Modules](https://aka.ms/avm) (`br/public:avm/res/...`), version-pinned.

## ⚠️ Cost & cleanup

These labs create real, billable resources. Running totals in East US 2, verified against the Azure retail price list on 4 Aug 2026:

| After deploying | Cost per hour |
|---|---|
| L1.1 — core deployment | ~$0.24 |
| L1.2 — architecture expansion | ~$1.65 |
| L1.3 — multi-service application | ~$1.73 |
| L1.4 — production-ready platform | ~$1.84 |

**Azure Firewall Standard is $1.25/hr of that on its own** — more than everything else in all four labs combined — and Bastion adds $0.19/hr. Both bill while deployed, whether or not anyone is using the lab. Budget ~$2.00–$2.25 for a full L1.4 demo hour including traffic.

Full breakdown: [`unit cost/`](unit%20cost/) — regenerate the handouts after any price or template change with `./unit\ cost/Build-CostDocs.ps1`.

When you're done (or pausing overnight), tear everything down:

**Classroom participants** (shared resource group — deletes resources, not the RG):
```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-techdemo-<yourname>" -WhatIf   # preview first
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-techdemo-<yourname>"
```

Or via the **Teardown labs** workflow in GitHub Actions — it runs against your `AZURE_RESOURCE_GROUP` secret, defaults to a dry run, and needs `DELETE` typed in to actually delete.

> [!WARNING]
> Don't delete just the firewall to save money. After L1.2 both spoke subnets route `0.0.0.0/0` at its private IP, so removing it alone black-holes the surviving VMs while they keep billing. Tear down the whole lab, or leave it running.
