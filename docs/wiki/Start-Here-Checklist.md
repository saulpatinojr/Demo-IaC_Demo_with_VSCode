# Start-Here Checklist

Work top to bottom. Each item is one small, checkable thing. If you can tick every box, your first deploy will work.

> New to the vocabulary (repo, fork, secret, OIDC)? Skim [Understanding IaC](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Understanding-IaC) and [GitHub Essentials](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/GitHub-Essentials) first — 10 minutes that make everything below make sense.

---

## 👤 A. Accounts you need

- [ ] **GitHub account** — https://github.com/join
- [ ] **GitHub Copilot** access — Free tier works for individuals. In a classroom org, your instructor will assign you a Copilot Business or Enterprise seat.
- [ ] **Azure access** — one of:
  - **Classroom participant:** Your instructor has pre-created a resource group (e.g. `rg-lab-<yourname>`) and granted you Contributor on it. They may have already run the OIDC setup for you. Confirm before going to Section G.
  - **Self-hosted:** An Azure subscription where you have at least Contributor and can create app registrations. Free trial: https://azure.microsoft.com/free

---

## 🧱 B. Bootstrap the installer script first

If `gh` is not installed yet, use this bootstrap path first.

- [ ] Create the installer bootstrap folder on the Desktop:

Copy/paste these lines one at a time:

```powershell
cd $HOME\Desktop
mkdir Demo-IaC-Bootstrap -ErrorAction SilentlyContinue
cd .\Demo-IaC-Bootstrap
```

- [ ] Download only the installer script over HTTPS:

```powershell
Invoke-WebRequest "https://raw.githubusercontent.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/main/scripts/Install-LabTools.ps1" -OutFile .\Install-LabTools.ps1
```

- [ ] If your machine blocks script download in terminal, download the same file in a browser and save it as:
  - `$HOME\Desktop\Demo-IaC-Bootstrap\Install-LabTools.ps1`

---

## 🛠️ C. Install the software

### Option 1 — One command (recommended for Windows lab workstations)

From **PowerShell 7 or PowerShell 5 (Run as Administrator)**, run the following:

```powershell
cd $HOME\Desktop\Demo-IaC-Bootstrap
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./Install-LabTools.ps1
```

When asked "Do you want to change the execution policy?" select "A" for Yes to All.

If PowerShell shows an execution-policy error, the second line fixes only the current shell session. This one-shot path installs tools, configures Git, and prepares sign-in. **Skip to Section D if you use this script.**

When the script reaches **Configuring Git**, enter values like these when prompted:

- Full name: `Student000001`
- Email: `Student000001@npluslab.onmicrosoft.com`

---

### Option 2 — Manual (Windows via winget, or macOS/Linux via download links)

| Tool | Why | winget | Download |
|------|-----|--------|----------|
| **Visual Studio Code** | Editor + Copilot agent mode | `winget install Microsoft.VisualStudioCode` | [code.visualstudio.com](https://code.visualstudio.com) |
| **Git** | Version control | `winget install Git.Git` | [git-scm.com](https://git-scm.com/downloads) |
| **GitHub Desktop** | Easy clone/commit/push UI | `winget install GitHub.GitHubDesktop` | [desktop.github.com](https://desktop.github.com) |
| **GitHub CLI (`gh`)** | Repo secrets, workflow runs from the terminal | `winget install GitHub.cli` | [cli.github.com](https://cli.github.com) |
| **Azure CLI (`az`)** | Deployments, what-if, testing | `winget install Microsoft.AzureCLI` | [learn.microsoft.com](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| **PowerShell 7** | Required for the setup and cleanup scripts | `winget install Microsoft.PowerShell` | [github.com/PowerShell](https://github.com/PowerShell/PowerShell/releases) |
| **Windows Terminal** | Better shell experience with tabs and PS7 support | `winget install Microsoft.WindowsTerminal` | [microsoft.com](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) |
| **Bicep CLI** | Compiles and lints templates | `az bicep install` (after Azure CLI) | — |

#### VS Code extensions

Open this repo in VS Code and accept the **recommended extensions** prompt — or install manually. The repository is set up to recommend the right VS Code extensions automatically when you first open the folder:

- [ ] **Bicep** — `code --install-extension ms-azuretools.vscode-bicep`
- [ ] **GitHub Copilot** — `code --install-extension GitHub.copilot`
- [ ] **GitHub Copilot Chat** — `code --install-extension GitHub.copilot-chat`
- [ ] **Azure CLI Tools** — `code --install-extension ms-vscode.azurecli`
- [ ] **GitHub Actions** — `code --install-extension github.vscode-github-actions`

#### Verify everything is on PATH

Open a **fresh** PowerShell 7 window after installing and run:

```bash
git --version
gh --version
az --version
az bicep version
pwsh --version
code --version
```

- [ ] All six print a version number (no "command not found").

---

## 🔐 D. Sign in

### GitHub CLI

Run this command first:

```powershell
gh auth login
```

Use this quick reference while answering prompts:

| Prompt in terminal | Choose / Do |
|---|---|
| Where do you use GitHub? | GitHub.com |
| Preferred protocol for Git operations? | HTTPS |
| Authenticate Git with your GitHub credentials? | Yes |
| How would you like to authenticate GitHub CLI? | Login with a web browser |

Then complete the browser flow:

| Step | Action |
|---|---|
| 1 | Copy the one-time code shown in the terminal |
| 2 | Press Enter when prompted to open the browser |
| 3 | Paste the code in the browser and finish sign-in |
| 4 | Return to PowerShell and wait for the success message |

Run this command last to confirm login:

```powershell
gh auth status
```

- [ ] `gh auth status` shows your GitHub username.

### GitHub Copilot CLI command

```powershell
gh copilot --version
```

`gh copilot` is a built-in stub in modern GitHub CLI (2.x+). The first time you run it, it will prompt:

> `GitHub Copilot CLI is not installed. Would you like to install it? (Y/n)`

Type **Y** and press Enter. After that, `gh copilot --version` will return a version number with no prompt.
`Install-LabTools.ps1` handles this automatically — no manual step needed when using the script.

If this says `gh: unknown command "copilot"`, update GitHub CLI (`winget upgrade GitHub.cli`) and reopen PowerShell.

- [ ] `gh copilot --version` prints a version number (no install prompt).
- [ ] `gh copilot suggest "list all files in a folder"` returns a suggested command.

### VS Code — Copilot Chat & GitHub Desktop

Because `gh auth login` stored a GitHub token on this machine, **VS Code and GitHub Desktop read that token automatically** — neither app needs a separate sign-in from scratch.

**GitHub Desktop first launch** will show two quick screens:

| Screen | What you see | What to do |
|---|---|---|
| Authorize GitHub Desktop | Your GitHub username is already shown under “Signed in as” | Click **Continue** |
| Configure Git | Name and email are pre-filled from `Install-LabTools.ps1` — the script ran `git config --global user.name` and `git config --global user.email` for you | Select **Use my GitHub account name and email address**, then click **Finish** |

**VS Code — Copilot Chat:**

- [ ] Open VS Code → press **`Ctrl+Alt+I`** to open Copilot Chat.
- [ ] If prompted to sign in, confirm the GitHub account shown matches the one used above.
- [ ] The Copilot icon appears in the sidebar and Chat responds to a test message.

### Azure CLI

```powershell
az login
```

A **Windows sign-in dialog** opens (not a browser tab). Complete these steps in order:

| Step | What you see | What to do |
|---|---|---|
| 1 | Account type screen | Choose **Work or school account** (classroom) or **Microsoft account** (personal/free trial) |
| 2 | Username field | Enter the account your instructor provided (e.g. `Student000001@npluslab.onmicrosoft.com`) |
| 3 | Password / temporary code field | Enter the **temporary code given by your instructor** |
| 4 | "Sign in to all apps and websites on this device?" | Click **No, this app only** — this is a lab machine, not your personal device |

Back in the terminal, you will see a **Tenant and subscription selection** table like this:

```
[Tenant and subscription selection]

No    Subscription name        Subscription ID                       Tenant
----- ------------------------ ------------------------------------ ----------
[1] * Azure Lab Subscriptions  a66afdab-e353-4499-b148-bf42c65b562b NetComPlus

The default is marked with an *; the default tenant is 'NetComPlus' and
subscription is 'Azure Lab Subscriptions' (a66afdab-...).
```

If only one subscription is listed it is already selected (marked `*`) — no action needed. Then confirm:

```powershell
az account show --query "{subscription:name, tenant:tenantId}" -o table
```

- [ ] `az account show` prints the correct subscription and tenant.

---

This completes Part 1 (A–D).

➡️ Continue with **[Start Here Checklist — Part 2](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist-Part-2)**