# Start Here Checklist — Part 2

Continue here after finishing [Start-Here Checklist](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist) sections A through D.

---

## 🍴 E. Fork the repo to your GitHub account

> **Why fork and not just clone?** GitHub Actions workflows can only read secrets from a repo you own. If you clone the instructor's repo directly, the workflows will fail at the secrets check. Your fork is your personal copy with your own secrets and workflow runs.

From **PowerShell** in your bootstrap folder, run:

```powershell
cd $HOME\Desktop\Demo-IaC-Bootstrap
Invoke-WebRequest "https://raw.githubusercontent.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/main/scripts/Connect-AzureAndGitHub.ps1" -OutFile .\Connect-AzureAndGitHub.ps1
./Connect-AzureAndGitHub.ps1
```

What this script does:

1. Validates your Azure CLI authentication (from Section D)
2. Validates your GitHub CLI authentication (from Section D)
3. Creates your fork at `https://github.com/<your-username>/Demo-IaC_Demo_with_VSCode` (if not yet forked)
4. Installs/verifies the `gh copilot` CLI extension

When it finishes you will see:

```
  > Forking the lab repo to your account
    [OK] Fork is ready at: https://github.com/<your-username>/Demo-IaC_Demo_with_VSCode
    [INFO] Use that URL in Section F of the checklist when cloning your copy of the repo.
```

- [ ] Script completes with `[OK] Fork is ready` (no red `[FAIL]` lines)
- [ ] Your fork URL is shown in the terminal — copy it, you will use it in Section F

> If your environment blocks script downloads in the terminal, download `Connect-AzureAndGitHub.ps1` in a browser, save it to `$HOME\Desktop\Demo-IaC-Bootstrap\`, then run it.

---

## 💻 F. Clone your fork to the Desktop

You have two ways to clone. Both end with the same folder on your Desktop.

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option A · Terminal clone (recommended)

> [!NOTE]
> **Best if you like the command line.** One command, stays in PowerShell, and sets up both `origin` and `upstream` remotes in one go.

Open a **new PowerShell 7** window and run (replace `<your-username>` with your GitHub username printed in Section E):

```powershell
cd $HOME\Desktop
gh repo clone <your-username>/Demo-IaC_Demo_with_VSCode
cd .\Demo-IaC_Demo_with_VSCode
git remote add upstream https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode.git
git remote -v
```

Expected output from `git remote -v`:

```
origin   https://github.com/<your-username>/Demo-IaC_Demo_with_VSCode.git (fetch)
origin   https://github.com/<your-username>/Demo-IaC_Demo_with_VSCode.git (push)
upstream https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode.git (fetch)
upstream https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode.git (push)
```

**Then set your fork as the default repo for `gh` commands.** Because you have two remotes (`origin` and `upstream`), `gh` will ask you to pick every time unless you set this once:

```powershell
gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode
```

You should see: `✓ Set <your-username>/Demo-IaC_Demo_with_VSCode as the default repository for the current directory`

<br>

---

## <img src="github-desktop.svg" width="30" align="top">&nbsp; Option B · GitHub Desktop clone (visual)

> [!TIP]
> **Best if you prefer a visual, point-and-click approach.** GitHub Desktop handles the clone — you then add the upstream remote in one terminal command.

**Clone in GitHub Desktop:**

1. Open **GitHub Desktop**
2. Click **File → Clone repository…**
3. Select the **URL** tab
4. Paste your fork URL: `https://github.com/<your-username>/Demo-IaC_Demo_with_VSCode`
5. Set **Local path** to: `C:\Users\<your-windows-username>\Desktop`
   *(GitHub Desktop appends the repo name — your final folder will be `...\Desktop\Demo-IaC_Demo_with_VSCode`)*
6. Click **Clone**

**Then add the upstream remote and set your fork as default** (run inside the cloned folder):

```powershell
cd "$HOME\Desktop\Demo-IaC_Demo_with_VSCode"
git remote add upstream https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode.git
git remote -v
gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode
```

<br>

---

- [ ] Folder `Demo-IaC_Demo_with_VSCode` exists on your Desktop
- [ ] `git remote -v` shows both `origin` (your fork) and `upstream` (instructor's repo)
- [ ] `gh repo set-default` confirmed your fork as the default repo
- [ ] Open the cloned folder in VS Code: `code "$HOME\Desktop\Demo-IaC_Demo_with_VSCode"` — accept the recommended extensions prompt.

---

## 🔗 G. Wire up GitHub → Azure (OIDC, one-time)

> **Before running any command in this section**, move into the cloned repo folder:
> ```powershell
> cd "$HOME\Desktop\Demo-IaC_Demo_with_VSCode"
> ```
> If you see `fatal: not a git repository`, you skipped Section F — go back and clone your fork first.

This creates a passwordless identity that GitHub Actions uses to deploy to Azure. All labs deploy into your single assigned resource group — they do not create their own.

> [!NOTE]
> **`gh secret list` will return nothing until this section is complete.** That is expected — the secrets do not exist yet. The Setup-Oidc script creates them. Only run the verification commands at the *end* of this section, after the script finishes.

---

### Step 1 — Check whether your instructor already ran setup for you

```powershell
gh secret list
```

| What you see | What it means | What to do |
|---|---|---|
| A list of secret names | Instructor already ran Setup-Oidc | Skip to **Step 3 — Verify** below |
| `no secrets found` | Setup has not been run yet | Continue to **Step 2** |

---

### Step 2 — Run Setup-Oidc

`-ResourceGroup` controls **where permissions are scoped** (classroom safety boundary).  
`-Prefix` controls **unique naming** (Entra app + lab resource names). It is optional in code, but for class labs you should still set it to avoid name collisions.

#### Classroom participant

> [!TIP]
> **Optional preview (`-WhatIf`)** — safe dry run. You should only see planned actions, with no changes applied.

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>" -WhatIf
```

#### Run for real

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"
```

#### Self-hosted (your own subscription)

> [!TIP]
> **Optional preview (`-WhatIf`)** — safe dry run. You should only see planned actions, with no changes applied.

```powershell
./scripts/Setup-Oidc.ps1 -Prefix "<yourname>" -WhatIf
```

#### Run for real

```powershell
./scripts/Setup-Oidc.ps1 -Prefix "<yourname>"
```

---

### Step 3 — Verify (run this only after the script completes)

```powershell
gh secret list
gh variable list
```

- [ ] `gh secret list` shows 6 secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`
  *(Self-hosted: 5 secrets — no `AZURE_RESOURCE_GROUP`)*
- [ ] `gh variable list` shows `AZURE_PREFIX` and `AZURE_LOCATION`

> Full walkthrough and manual steps: [Deployment Guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Deployment-Guide). Instructor pre-lab setup: [Instructor Setup](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Instructor-Setup).

---

## 🚀 H. First deploy (L1)

- [ ] On GitHub, open **Actions** and click the green **"I understand my workflows, go ahead and enable them"** button if prompted (forks disable workflows by default).
- [ ] Run **Deploy L1 — Hub & Spoke** → **Run workflow** → **Run workflow**.
- [ ] Watch the **What-if** step — it lists every resource that will be created. Read it before the deploy step runs.
- [ ] Green check on all three steps (Lint → What-if → Deploy)? 🎉 Continue with the **[L1 guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/L1-Hub-and-Spoke)**.

---

## Quick "am I ready?" self-test

| Question | Where to fix if "no" |
|---|---|
| `gh auth status` shows my GitHub username? | Part 1 — Section D |
| `az account show` prints the correct subscription? | Part 1 — Section D |
| Fork exists at `github.com/<me>/Demo-IaC_Demo_with_VSCode`? | Section E |
| Local clone exists on Desktop? | Section F |
| `git remote -v` shows both `origin` and `upstream`? | Section F |
| `gh repo set-default` points to my fork (not the instructor's)? | Section F |
| `gh secret list` shows `AZURE_RESOURCE_GROUP` and 5 others? | Section G |
| `gh variable list` shows `AZURE_PREFIX` and `AZURE_LOCATION`? | Section G |
| The Actions tab shows the deploy workflows (not blocked)? | Section H |

Stuck on any of these → [Troubleshooting](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Troubleshooting).

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Secrets versus variables**
>
> **You just used it:** `Setup-Oidc.ps1` pushed both kinds. `AZURE_PREFIX` and `AZURE_LOCATION` went in as **variables** because they appear in resource names and logs anyway. The passwords and IDs went in as **secrets**.
> **Find it:** **Settings → Secrets and variables → Actions**. You can read a variable back; you can never read a secret back, only replace it. In a run log a secret prints as `***`, automatically.
> **Beyond the lab:** the test is simple — if someone leaking it would cause harm, it is a secret; if you would happily print it in a log, it is a variable. Getting that split right is most of what secret hygiene means in practice.
> [Docs →](https://docs.github.com/actions/security-guides/using-secrets-in-github-actions)
