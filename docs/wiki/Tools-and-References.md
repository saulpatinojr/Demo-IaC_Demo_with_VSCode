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
- Used for: secrets (`gh secret set`), variables (`gh variable set`), running workflows (`gh workflow run "Curriculum L1.1 - Core Deployment"`), monitoring runs (`gh run watch`)

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

### `Connect-AzureAndGitHub.ps1` — self-hosted only
- Fork + auth helper: validates Azure/GitHub auth, creates your GitHub fork, and verifies `gh copilot` is available.
- **Classroom accounts never run this** — your fork is pre-created; just open it in the browser.
- Typical use (after `gh auth login`): `./scripts/Connect-AzureAndGitHub.ps1`
- Idempotent — existing fork/auth state is detected and reused.

### `Load-LabSettings.ps1`
- Loads your lab values from `lab-settings.csv` into environment variables for the current terminal session.
- Copy `lab-settings.csv.example` → `lab-settings.csv`, fill in your values, then run: `./scripts/Load-LabSettings.ps1`
- Use `-Persist` once to save variables so they survive terminal restarts. **Windows only** — .NET has no user environment store on macOS or Linux, and the script says so instead of silently saving nothing.
- `-Persist` stores your VM and SQL passwords in plain text (`HKCU\Environment`). Fine for a throwaway lab machine; remove them afterwards on your own machine with `./scripts/Load-LabSettings.ps1 -Clear`.

### `Clear-LabCredentials.ps1`
- Takes the lab off **your machine**: signs out of `az` and `gh`, removes the values `-Persist` saved, and deletes `lab-settings.csv` (which holds your passwords in plain text).
- Deletes nothing in Azure. It checks first and warns if resources are still deployed, because once you are signed out you can no longer tear them down and they keep billing.
- Always preview: `./scripts/Clear-LabCredentials.ps1 -WhatIf` · Keep your values for a later run with `-KeepSettingsFile`.
- Full walkthrough: [Cleanup & Reset](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Cleanup-and-Reset).

### `Setup-Oidc.ps1` — self-hosted only
- One-command GitHub↔Azure OIDC handshake: creates the Entra app registration, adds the federated credential, grants Contributor on your resource group, and pushes all repo secrets and variables.
- **Classroom accounts never run this** (Reader role, and no need — the shared workshop identity is already federated to your fork and the workflows carry in-code defaults, so zero secrets is the correct state).
- Always preview first: `./scripts/Setup-Oidc.ps1 -ResourceGroup "<your-rg>" -Prefix "<yourname>" -WhatIf` — `-ResourceGroup` is required on every run, preview included, and the group must already exist.
- Idempotent — re-running refreshes the identity and resource-group secrets, and keeps existing VM/SQL passwords so they still match anything already deployed.
- Full walkthrough: [Deployment Guide → self-hosted appendix](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Deployment-Guide).

<details><summary><b>Why these scripts pipe secrets in instead of using <code>--body -</code></b> (maintainer note)</summary>

Both OIDC scripts set secrets by piping the value and passing **no** `--body`:

```powershell
$value | gh secret set NAME --repo $repo      # correct
$value | gh secret set NAME --repo $repo --body -   # WRONG: stores the literal "-"
```

`gh` reads a value from standard input **only when `--body` is absent**. Its own flag help says so, identically for both commands:

```
$ gh secret set --help
  -b, --body string   The value for the secret (reads from standard input if not specified)

$ gh variable set --help
  -b, --body string   The value for the variable (reads from standard input if not specified)
```

`--body -` *specifies* a value, so stdin is never read and the secret is stored as the one-character string `-`. Every `azure/login` then fails with an opaque AAD error, because a stored secret — even a one-character garbage one — always overrides the workflow's in-code fallback.

**This has been confirmed against the real client** (`gh` 2.63.2), by pointing it at a local HTTPS server and reading the request it actually sent. A repo secret is encrypted client-side with a libsodium sealed box, which is exactly **48 bytes larger than its plaintext** — so the ciphertext length recovers the plaintext length without ever decrypting anything. Piping the 9-character string `realvalue` both ways:

| invocation | ciphertext | plaintext length |
|---|---|---|
| `gh secret set X --body -` | 49 B | **1** — the literal `-`, stdin discarded |
| `echo … \| gh secret set X` | 57 B | **9** — `realvalue`, read from stdin |

That length of 1 is the bug. Nothing about it is specific to this repo or to Azure.

**Re-checking it yourself, using a variable.** A secret cannot be read back, so confirming a *stored* value normally needs a throwaway workflow that echoes its length. A **variable** can be read back directly, which turns the check into two commands. `gh variable set` and `gh secret set` are separate commands that share the `--body` semantics quoted above — and the same local capture showed `variable set --body -` putting `{"name":"…","value":"-"}` on the wire — so the variable is a faithful stand-in:

```bash
# On a fork you don't mind writing to:
echo "realvalue" | gh variable set TEST_BODY_DASH --repo OWNER/REPO --body -
gh variable get TEST_BODY_DASH --repo OWNER/REPO

# Cleanup
gh variable delete TEST_BODY_DASH --repo OWNER/REPO
```

`-` confirms the behaviour these scripts work around. `realvalue` would mean a future `gh` release changed it, and the piping could be reverted.

</details>

### `Cleanup-Labs.ps1` — self-hosted only
- Deletes every resource inside your lab resource group — all labs share one group, so this clears them in one run. The group itself is kept.
- **Classroom accounts use the "Teardown labs" workflow instead** (Actions tab — dry-run by default, type `DELETE` to confirm). Reader on the group means this script cannot delete anything for you.
- Always preview first: `./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP -WhatIf`
- Leave `-ResourceGroup` off and it falls back to the `AZURE_RESOURCE_GROUP` environment variable.
- Add `-RemoveOidc` to also delete the Entra app registration and its role assignment. **Self-hosted only** — in the classroom that app is the shared identity for the whole class; deleting it is instructor-only and would break everyone's deploys.

---

## 🔒 Admin scripts (`scripts/admin/`) — Instructor only

These scripts require **Owner or User Access Administrator** on the subscription. `New-LabEnvironment.ps1` uses the Az PowerShell module (`Install-Module Az -Scope CurrentUser`); `Set-LabPolicy.ps1` and `Enable-DefenderPlans.ps1` deploy **Bicep templates** through the Azure CLI. Students never run these.

### `Setup-OidcAll.ps1`
- Instructor-run bulk OIDC setup: for every student in `lab-user-data.csv`, creates an Entra app registration, federated credentials, a Contributor role assignment on the student's resource group, and pushes the GitHub secrets + variables to the student's fork (`User<nn>-TechCon`).
- The current classroom event runs on a **single shared deploy identity** instead — one app, one federated credential per fork, and **no per-fork secrets** (the workflows' in-code fallbacks cover everything). Maintaining that shared app's federated credentials — including the `AADSTS700213` subject-format fix — is documented in [FIX-STUDENT-DEPLOYMENTS.md](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/FIX-STUDENT-DEPLOYMENTS.md).
- Run **after** `New-LabEnvironment.ps1`. When complete, students only need to enable workflows on their fork and run L1.1.
- Always preview first: `./scripts/admin/Setup-OidcAll.ps1 -WhatIf`
- Idempotent — safe to re-run to repair or rotate credentials.
- Requires `gh` auth with Admin access to each student's fork.

### `New-LabEnvironment.ps1`
- Reads `lab-user-data.csv` from the same folder (auto-detects instructor from `Type = Instructor` row).
- Bulk-provisions all student environments: creates one resource group per student, **named exactly like the student's GitHub account** (`User<nn>-TechCon` — the workflows target it by fork-owner name), applies 4 required tags (`Owner`, `Event`, `Date`, `Instructor`), grants each student **Reader** on their own RG (the shared deploy identity holds Contributor), and assigns the instructor Contributor on all RGs.
- Optional: creates a User Assigned Managed Identity (`<username>-mi`) per student (`-IncludeManagedIdentity`).
- Always preview first: `./scripts/admin/New-LabEnvironment.ps1 -WhatIf`
- Idempotent — safe to re-run; existing resources are detected and skipped.
- Full guide: [Instructor Setup](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Instructor-Setup).

### `Set-LabPolicy.ps1`
- Assigns **6 Azure Policy assignments** to every student resource group:
  - **Allowed locations** — restricts deployments to `eastus2` and `westus2` (L1.4's failover region)
  - **Allowed resource types** — whitelist of ~38 types used by L1.1–L1.4 labs
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
