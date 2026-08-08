# Tools and References

> For a hands-on warm-up instead of a reference, see [Getting Comfortable with the Tools](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Getting-Comfortable-with-the-Tools).

---

## 🧰 Applications

### Visual Studio Code
- Install: `winget install Microsoft.VisualStudioCode` · [download](https://code.visualstudio.com/download)
- This repo recommends extensions automatically (`.vscode/extensions.json`) — accept the prompt when you first open the folder.
- Docs: https://code.visualstudio.com/docs

### GitHub Copilot (agent mode)
- Install the **GitHub Copilot** and **GitHub Copilot Chat** extensions in VS Code, then sign in with your GitHub account.
- Open chat with `Ctrl+Alt+I` and set the mode dropdown to **Agent**. Agent mode reads and edits multiple files and runs terminal commands (like `az bicep build`) with your approval.
- Docs: https://code.visualstudio.com/docs/copilot/chat/chat-agent-mode · https://docs.github.com/copilot

### Bicep extension for VS Code
- Marketplace ID: `ms-azuretools.vscode-bicep`
- Gives IntelliSense for AVM module parameters — hover any `br/public:avm/...` reference to see the module's parameter docs.
- Docs: https://learn.microsoft.com/azure/azure-resource-manager/bicep/visual-studio-code

### Windows Terminal
- Install: `winget install Microsoft.WindowsTerminal`
- Recommended shell for the workshop — supports PowerShell 7 tabs and a cleaner experience than the default console.

### Git and GitHub Desktop
- Git: `winget install Git.Git` · [git-scm.com](https://git-scm.com/downloads)
- GitHub Desktop: `winget install GitHub.GitHubDesktop` · [desktop.github.com](https://desktop.github.com/) — used in the labs for clone/commit/push without needing to memorise git commands.
- Docs: https://docs.github.com/desktop

---

## 💻 CLIs

### Azure CLI (`az`)
- Install: `winget install Microsoft.AzureCLI` · [install docs](https://learn.microsoft.com/cli/azure/install-azure-cli)
- Sign in: `az login` · Select subscription: `az account set --subscription "<name-or-id>"`
- Key commands in this workshop: `az deployment group create`, `az deployment group what-if`, `az group show`, `az vm run-command invoke`, `az sql failover-group set-primary`

### Bicep CLI
- Install via Azure CLI: `az bicep install` · Upgrade: `az bicep upgrade`
- Key commands: `az bicep build --file <f>` (compile + lint), `az bicep restore` (pull AVM modules from registry), `az bicep build-params --file <f>.bicepparam`
- Docs: https://learn.microsoft.com/azure/azure-resource-manager/bicep/

### GitHub CLI (`gh`)
- Install: `winget install GitHub.cli` · [cli.github.com](https://cli.github.com/)
- Sign in: `gh auth login`
- Used for: secrets (`gh secret set`), variables (`gh variable set`), running workflows (`gh workflow run "Deploy L1 - Hub & Spoke"`), monitoring runs (`gh run watch`)

### PowerShell 7 (`pwsh`)
- Install: `winget install Microsoft.PowerShell`
- Required for the setup and cleanup scripts. PowerShell 5 (built into Windows) also works for most commands, but PS7 is recommended.

---

## 🗂️ Repo scripts (`scripts/`)

PowerShell helpers you run on your own machine (requires PowerShell 7 + signed-in `az` and `gh`).

### `Install-LabTools.ps1`
- One-command workstation setup: installs all tools above, configures git, installs VS Code extensions, signs you into GitHub and Azure.
- Run as Administrator: `./scripts/Install-LabTools.ps1`
- Idempotent — already-installed tools are skipped.

### `Connect-AzureAndGitHub.ps1`
- Fork + auth helper: validates Azure/GitHub auth, creates your GitHub fork, and verifies `gh copilot` is available.
- Typical use (after `gh auth login`): `./scripts/Connect-AzureAndGitHub.ps1`
- Idempotent — existing fork/auth state is detected and reused.

### `Load-LabSettings.ps1`
- Loads your lab values from `lab-settings.csv` into environment variables for the current terminal session.
- Copy `lab-settings.csv.example` → `lab-settings.csv`, fill in your values, then run: `./scripts/Load-LabSettings.ps1`
- Use `-Persist` once to save variables permanently (survive terminal restarts).

### `Setup-Oidc.ps1`
- One-command GitHub↔Azure OIDC handshake: creates the Entra app registration, adds the federated credential, grants Contributor on your resource group, and pushes all repo secrets and variables.
- Always preview first: `./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-techdemo-<yourname>" -Prefix "<yourname>" -WhatIf` — `-ResourceGroup` is required on every run, preview included, and the group must already exist.
- Idempotent — re-running refreshes the identity and resource-group secrets, and keeps existing VM/SQL passwords so they still match anything already deployed.
- Full walkthrough: [Deployment Guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Deployment-Guide).

### `Cleanup-Labs.ps1`
- Deletes every resource inside your lab resource group — all four labs share one group, so this clears L1–L4 in one run. The group itself is kept.
- Always preview first: `./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP -WhatIf`
- Leave `-ResourceGroup` off and it falls back to the `AZURE_RESOURCE_GROUP` environment variable.
- Add `-RemoveOidc` to also delete the Entra app registration and its role assignment.

---

## 🔒 Admin scripts (`scripts/admin/`) — Instructor only

These scripts require the **Az PowerShell module** (`Install-Module Az -Scope CurrentUser`) and **Owner or User Access Administrator** on the subscription. Students never run these.

### `Setup-OidcAll.ps1`
- Instructor-run bulk OIDC setup: for every student in `lab-user-data.csv`, creates the Entra app registration, federated credentials, Contributor role assignment, and pushes all 6 GitHub secrets + 2 variables to the student's fork.
- Run **after** `New-LabEnvironment.ps1`. When complete, students skip straight to Section G → Step 3 (Verify).
- Always preview first: `./scripts/admin/Setup-OidcAll.ps1 -WhatIf`
- Idempotent — safe to re-run to repair or rotate credentials.
- Requires `gh` auth with Admin access to each student's fork.

### `New-LabEnvironment.ps1`
- Reads `lab-user-data.csv` from the same folder (auto-detects instructor from `Type = Instructor` row).
- Bulk-provisions all student environments: creates `rg-techdemo-<username>`, applies 4 required tags (`Owner`, `Event`, `Date`, `Instructor`), assigns each student Contributor on their own RG, and assigns the instructor Contributor on all RGs.
- Optional: creates a User Assigned Managed Identity (`<username>-mi`) per student (`-IncludeManagedIdentity`).
- Always preview first: `./scripts/admin/New-LabEnvironment.ps1 -WhatIf`
- Idempotent — safe to re-run; existing resources are detected and skipped.
- Full guide: [Instructor Setup](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Instructor-Setup).

### `Set-LabPolicy.ps1`
- Assigns **6 Azure Policy assignments** to every `rg-techdemo-*` resource group:
  - **Allowed locations** — restricts deployments to `eastus2` and `westus2` (L4's failover region)
  - **Allowed resource types** — whitelist of ~38 types used by L1–L4 labs
  - **Inherit tag × 4** — `Owner`, `Event`, `Date`, `Instructor` propagate automatically from RG to all child resources
- Run after `New-LabEnvironment.ps1`.
- Always preview first: `./scripts/admin/Set-LabPolicy.ps1 -WhatIf`
- Idempotent — existing assignments are skipped.

---

## 🔗 Key references

| Topic | Link |
|-------|------|
| Azure Verified Modules (AVM) index | https://aka.ms/avm |
| AVM module source and docs | https://github.com/Azure/bicep-registry-modules |
| Bicep documentation | https://learn.microsoft.com/azure/azure-resource-manager/bicep/ |
| Bicep parameter files (.bicepparam) | https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files |
| GitHub Actions OIDC to Azure | https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect |
| azure/login action | https://github.com/Azure/login |
| Hub-spoke network topology | https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke |
| Azure Firewall DNAT | https://learn.microsoft.com/azure/firewall/tutorial-firewall-dnat |
| Container Apps | https://learn.microsoft.com/azure/container-apps/ |
| Private endpoints | https://learn.microsoft.com/azure/private-link/private-endpoint-overview |
| SQL failover groups | https://learn.microsoft.com/azure/azure-sql/database/failover-group-sql-db |
| Azure Front Door | https://learn.microsoft.com/azure/frontdoor/ |
| Azure pricing calculator | https://azure.microsoft.com/pricing/calculator/ |

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Pinned versions and automated updates**
>
> **You just used it:** every Azure Verified Module in these templates is pinned to an exact version — `avm/res/network/virtual-network:0.9.0`, never `:latest`. Your deploy today and the same deploy next month produce identical infrastructure.
> **Find it:** any `br/public:avm/...` line in a `main.bicep`. The version is the text after the final colon.
> **Beyond the lab:** pinning makes builds reproducible; Dependabot then proposes version bumps as pull requests, so upgrades become a reviewed decision instead of a surprise.
> [Docs →](https://docs.github.com/code-security/dependabot/dependabot-version-updates/about-dependabot-version-updates)
