# Start-Here Checklist

> [!TIP]
> New to the vocabulary — repo, fork, secret, OIDC? Skim [Understanding IaC](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Understanding-IaC) and [GitHub Essentials](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/GitHub-Essentials) first. Ten minutes that make everything below make sense.

## 🏫 Classroom (pre-staged) — start here

If you are in the instructor-led workshop, there is **nothing to install**. Four steps and you are deploying:

1. **Sign in to GitHub** as your workshop account (`User<nn>-TechCon`, e.g. `User01-TechCon`).
2. **Open your fork** in the browser: `github.com/<your-account>/Demo-IaC_Demo_with_VSCode`.
3. Open the **Actions** tab and click the green **"I understand my workflows, go ahead and enable them"** button (forks disable workflows by default).
4. Go to **[L1.1 — Core Deployment](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-1-Core-Deployment)** and run your first deploy. Done.

Everything else is **already done for you**:

| Already staged | Details |
|---|---|
| **Your fork** | Pre-created at `github.com/<your-account>/Demo-IaC_Demo_with_VSCode` |
| **Your resource group** | Pre-created, named **exactly like your GitHub account** (e.g. `User01-TechCon`) — the workflows target it automatically |
| **Deploy identity** | A shared workshop identity, federated to your fork — deployments need **no repo secrets**. `gh secret list` showing `no secrets found` is the normal, correct state |
| **VM / SQL passwords** | Default to `<your-account>!!` (e.g. `User01-TechCon!!`) |

Your own Azure role is **Reader** — you verify what got built in the portal, while the deployments run through GitHub Actions under the shared identity (which holds Contributor on your group). That also means local `az deployment ...` commands will fail for you — deploy through the Actions tab.

The main curriculum path runs **east: L1.1 → L2.1 → L3.1 → L4.1** — one foundation chapter per level. The full grid of all 22 chapters is on the **[Curriculum Map](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Map)**.

> [!NOTE]
> Want the full **VS Code + Copilot + CLI** experience on top of the browser-only path — or are you running the workshop **at home on your own subscription**? Continue below. Otherwise you can stop reading this page now.

---

## 🛠️ Self-hosted / at-home setup (Sections A–D)

Work top to bottom. Each item is one small, checkable thing. These tool installs are needed for the Copilot/CLI experience (classroom included, if you want it) and for self-hosted deploys from your own subscription.

> [!IMPORTANT]
> **You need Windows 11.** Section C installs the toolchain with `winget`, which is Windows-only, and the settings helper writes to the Windows user environment store. macOS and Linux are **not supported today** — see [Getting Comfortable with the Tools](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Getting-Comfortable-with-the-Tools) for exactly which two dependencies block them.

### Which are you?

<table>
<tr>
<td align="center" width="360"><img src="icon-instructor.svg" width="56"><br><br><b>Classroom participant</b><br><sub>Fork, resource group and deploy identity already staged — install tools only if you want the Copilot/CLI experience</sub></td>
<td align="center" width="360"><img src="icon-self-service.svg" width="56"><br><br><b>I'm on my own</b><br><sub>Own subscription — create the group, run the OIDC setup yourself</sub></td>
</tr>
</table>

---

## 👤 A. Accounts you need

- [ ] **GitHub account** — https://github.com/join
- [ ] **GitHub Copilot** access — Free tier works for individuals. In a classroom org, your instructor will assign you a Copilot Business or Enterprise seat.
- [ ] **Azure access** — one of:
  - **Classroom participant:** Nothing to set up. Your resource group is pre-created and named after your GitHub account (e.g. `User01-TechCon`), and you hold **Reader** on it — the shared workshop deploy identity holds Contributor and does the deploying for you.
  - **Self-hosted:** An Azure subscription where you have at least **Contributor and can create app registrations** — that is the self-hosted requirement, not the classroom one. Free trial: https://azure.microsoft.com/free — you create the resource group yourself, once, when you run the OIDC setup ([Part 2, self-hosted section](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist-Part-2)).

> [!NOTE]
> **Self-hosted only — don't type `<your-rg>` literally.** Every lab deploys into one group that must already exist in your subscription. After `az login` in Section D, list what you actually have and use that exact string everywhere below:
> ```powershell
> az group list --query "[].name" -o tsv
> ```
> (Classroom accounts can skip this — the group name **is** your GitHub account name.)

---

## 🧱 B. Bootstrap the installer script first

If `gh` is not installed yet, use this bootstrap path first.

- [ ] Create the installer bootstrap folder on the Desktop:

Copy/paste these lines one at a time:

```powershell
mkdir "$env:PUBLIC\Demo-IaC-Bootstrap" -Force | Out-Null
cd "$env:PUBLIC\Demo-IaC-Bootstrap"
```

- [ ] Download only the installer script over HTTPS:

```powershell
Invoke-WebRequest "https://raw.githubusercontent.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/main/scripts/Install-LabTools.ps1" -OutFile .\Install-LabTools.ps1
```

> [!TIP]
> **Certificate or TLS error on the download?** It is per-machine state, not your account (OneDrive-synced profiles do not roam certificate stores). Fix in this order:
> 1. Check the clock -- `Get-Date`. A wrong date invalidates every certificate: `w32tm /resync /force`
> 2. Force TLS 1.2 for this session, then retry the download:
>    `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`
> 3. Open `https://github.com` once in Edge -- Windows fetches missing root certificates on first use -- then retry.

- [ ] If your machine blocks script download in terminal, download the same file in a browser and save it as:
  - `C:\Users\Public\Demo-IaC-Bootstrap\Install-LabTools.ps1` (the same folder the previous step created -- Public is shared, so it works no matter which account is signed in)

---

## 🛠️ C. Install the software

### Option 1 — One command (recommended for Windows lab workstations)

From **PowerShell 7 or PowerShell 5 (Run as Administrator)**, run the following:

```powershell
cd "$env:PUBLIC\Demo-IaC-Bootstrap"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
./Install-LabTools.ps1
```

> [!TIP]
> **Certificate error `0x8a15005e` ("server certificate did not match") from winget?** That machine has a stale preinstalled App Installer whose msstore certificates are outdated -- per-machine, not your profile. The script pins every install to the `winget` source, which sidesteps msstore entirely. If it still appears, install PowerShell 7 directly and re-run the script:
> ```powershell
> winget install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements
> ./Install-LabTools.ps1
> ```
> For other certificate/TLS errors: check the clock (`Get-Date`, fix with `w32tm /resync /force`), then `winget source reset --force` and re-run.

> [!NOTE]
> **On a brand-new machine this script runs in two stages.** Stage 1 installs PowerShell 7 and asks you to close the window — that is expected, not an error. Open a **new** PowerShell window (Run as Administrator), run this same block again, and the script detects PowerShell 7, switches to it, and installs everything else (stage 2). If PowerShell 7 was already present, there is only one stage.

If PowerShell shows an execution-policy error, the second line fixes only the current shell session. This one-shot path installs tools, configures Git, and prepares sign-in. **Skip to Section D if you use this script.**

When the script reaches **Configuring Git**, enter values like these when prompted:

- Full name: `Student000001`
- Email: `Student000001@npluslab.onmicrosoft.com`

---

### Option 2 — Manual (Windows 11, via winget or the download links)

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

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Forks and the `upstream` remote**
>
> **You just used it:** your fork is a complete, independent copy of this repo — your own Actions runs, your own history. Nothing you do can affect anyone else's.
> **Find it:** `git remote -v` in your clone. `origin` is your fork; `upstream` points at the original, which is how you pull in later changes without losing your work.
> **Beyond the lab:** this is how essentially all open-source contribution works: fork, branch, pull request. The workshop uses it so twenty people can deploy from twenty repos with no coordination.
> [Docs →](https://docs.github.com/pull-requests/collaborating-with-pull-requests/working-with-forks/about-forks)
