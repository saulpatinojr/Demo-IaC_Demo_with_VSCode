# IaC Demo — Bicep + GitHub Copilot + GitHub Actions → Azure

Learn to author **Azure Bicep** infrastructure-as-code with **GitHub Copilot agent mode in VS Code**, built entirely from **Azure Verified Modules (AVM)**, and deploy it to Azure with **GitHub Actions (OIDC)** — no stored cloud credentials.

The demo is four **cumulative lab stages**. Each stage builds on the infrastructure the previous one deployed, and each gives you 2–3 ways to test what you built:

| Stage | What you build | What it adds | Tests |
|-------|----------------|--------------|-------|
| **[L1 — Hub & Spoke](../../wiki/L1-Hub-and-Spoke)** | Hub + spoke VNets (peered), Bastion, 1 Linux VM | Core networking & connectivity | Bastion SSH, cross-peering curl/ping, peering state check |
| **[L2 — Web Tier & Firewall](../../wiki/L2-Web-Tier-and-Firewall)** | 3 nginx VMs behind an internal LB, Azure Firewall (DNAT + egress control), NSGs, route tables | Traffic inspection & load balancing | Round-robin curl via firewall, blocked vs allowed egress, NSG flow verify |
| **[L3 — Containers & Data](../../wiki/L3-Containers-and-Data)** | Azure Container Apps, Azure SQL, Key Vault, managed identity, monitoring + alerting | Containers, data tier, **private networking** (private endpoints, no public data plane) | Hit the app URL, prove SQL is private-only, trigger an alert |
| **[L4 — Global Scale](../../wiki/L4-Global-Scale)** | Second region, SQL failover group, Azure Front Door | Multi-region HA & global entry point | Front Door URL, simulated regional failover, SQL failover group |

> 📖 **The full workshop guide lives in the [Wiki](../../wiki).**
> - Brand new to any of this? Start with the **[Start-Here Checklist](../../wiki/Start-Here-Checklist)** and **[Understanding IaC](../../wiki/Understanding-IaC)**.
> - New to GitHub itself (repos, Actions, secrets vs. variables)? **[GitHub Essentials](../../wiki/GitHub-Essentials)**.
> - Want to get comfortable with VS Code, Bicep, and Copilot first? **[Getting Comfortable with the Tools](../../wiki/Getting-Comfortable-with-the-Tools)**.

---

## 1. Install the software

Everything installs on Windows via `winget` (or use the download links). macOS/Linux users: use the links.

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

> **Classroom participants:** your instructor has pre-created a resource group for you (e.g. `rg-lab-<yourname>`) and granted you Contributor on it. Use `-ResourceGroup` and `-Prefix` so the script scopes access correctly and avoids name conflicts with other participants.

```powershell
./scripts/Setup-Oidc.ps1 -WhatIf   # preview — changes nothing
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"
```

`-ResourceGroup` is required for real runs in this repo because deploy workflows expect the `AZURE_RESOURCE_GROUP` secret.

This creates the Entra app + service principal, adds a federated credential for your fork's branch, grants Contributor on your assigned resource group, and pushes all the required repo secrets and variables (including strong throwaway VM/SQL passwords it generates for you). Re-run any time to rotate.

**Secrets set:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`  
**Variables set:** `AZURE_PREFIX` (your unique prefix), `AZURE_LOCATION` (defaults to `eastus2`)

After setup succeeds, trigger **Deploy L1 - Hub & Spoke** in GitHub Actions (`Actions` tab -> select workflow -> `Run workflow`).

> Want to understand each step, or on macOS/Linux? The manual `az`/`gh` walkthrough is in **[Wiki → Deployment Guide](../../wiki/Deployment-Guide)**. New to secrets vs. variables? See **[Wiki → GitHub Essentials](../../wiki/GitHub-Essentials)**.

## 5. Start the workshop

Head to the **[Wiki Home](../../wiki)** and begin with **L1**. Each lab guide shows you the Copilot agent-mode prompts to author/modify the Bicep, the workflow to deploy it, and the tests to prove it works.

## Repo map

```
labs/
  L1-hub-spoke/     hub+spoke, Bastion, test VM
  L2-web-tier/      internal LB + 3 web VMs + Azure Firewall
  L3-containers/    Container Apps, SQL, Key Vault, monitoring, private endpoints
  L4-global/        second region, SQL failover group, Front Door
  modules/          the only two non-AVM modules (subnet-on-existing-VNet, failover group)
scripts/
  Connect-AzureAndGitHub.ps1  auto-fork + clone helper (sets upstream remote)
  Setup-Oidc.ps1    one-command GitHub↔Azure OIDC handshake (+ repo secrets)
  Cleanup-Labs.ps1  tear down lab resource groups (and optionally the OIDC identity)
.github/workflows/  deploy-l1..l4.yml + teardown.yml (all OIDC, all manual dispatch)
bicepconfig.json    linter settings
```

All Azure resources come from [Azure Verified Modules](https://aka.ms/avm) (`br/public:avm/res/...`), version-pinned.

## ⚠️ Cost & cleanup

These labs create real, billable resources — **Azure Firewall (~$1.25/hr) and Bastion are the big ones**. When you're done (or pausing overnight), tear everything down:

**Classroom participants** (shared resource group — deletes resources, not the RG):
```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-<yourname>" -WhatIf   # preview first
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-<yourname>"
```

**Standard / self-hosted** (deletes the lab resource groups entirely):
```powershell
./scripts/Cleanup-Labs.ps1 -WhatIf   # preview, then run without -WhatIf
```

Or via **Teardown labs** workflow in GitHub Actions (type `DELETE` to confirm), or the raw CLI:

```bash
az group delete -n rg-iacdemo-l4 -y; az group delete -n rg-iacdemo-l3 -y
az group delete -n rg-iacdemo-l2 -y; az group delete -n rg-iacdemo-l1 -y
```
