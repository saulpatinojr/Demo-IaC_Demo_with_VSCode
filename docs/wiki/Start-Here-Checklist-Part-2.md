# Start Here Checklist — Part 2

Continue here after finishing [Start-Here Checklist](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist) sections A through D — or, if you are a **classroom participant**, jump straight to **Section H** below.

---

## ✅ Already done for you (classroom)

Two whole setup chapters of this page do not apply to classroom accounts, because they were done before you arrived:

- **Your fork already exists** at `github.com/<your-account>/Demo-IaC_Demo_with_VSCode` — nothing to fork, no script to run.
- **The deploy identity is already wired.** A shared workshop identity carries a federated credential for your fork, and the workflows carry in-code defaults for everything else — target resource group (your account name), prefix, and passwords (`<your-account>!!`). Your fork needs **zero secrets and zero variables**: `gh secret list` returning `no secrets found` is the normal, correct state, not something to fix.

Your classroom path on this page: **Section F** (optional — only if you want the Copilot/CLI experience), then **Section H** — your first deploy.

The fork-and-OIDC setup lives on under **[Self-hosted setup (Sections E & G)](#-self-hosted-setup-sections-e--g)** for people running on their own subscription.

---

## 💻 F. Clone your fork to C:\Users\Public — only needed for the Copilot/CLI path

> [!NOTE]
> **Classroom:** this section is optional. Deploying and verifying happens entirely in the browser (Actions tab + Azure portal). Clone only if you want to edit Bicep locally with VS Code and Copilot.

You have two ways to clone. Both end with the same folder: `C:\Users\Public\Demo-IaC_Demo_with_VSCode`.

> [!IMPORTANT]
> **Why not the Desktop?** On these lab machines the Desktop is synced by OneDrive under a shared Microsoft account, so a git repo cloned there syncs its `.git` folder across every station — git operations race the sync client and clones cross-contaminate between lanes. `C:\Users\Public` is local to each machine and never syncs.

<br>

---

### <img src="gh-actions.png" width="30" align="top">&nbsp; Option A · Terminal clone (recommended)

> [!NOTE]
> **Best if you like the command line.** One command, stays in PowerShell, and sets up both `origin` and `upstream` remotes in one go.

Open a **new PowerShell 7** window and run (replace `<your-username>` with your GitHub account name):

```powershell
cd $env:PUBLIC
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

### <img src="github-desktop.svg" width="30" align="top">&nbsp; Option B · GitHub Desktop clone (visual)

> [!TIP]
> **Best if you prefer a visual, point-and-click approach.** GitHub Desktop handles the clone — you then add the upstream remote in one terminal command.

**Clone in GitHub Desktop:**

1. Open **GitHub Desktop**
2. Click **File → Clone repository…**
3. Select the **URL** tab
4. Paste your fork URL: `https://github.com/<your-username>/Demo-IaC_Demo_with_VSCode`
5. Set **Local path** to `C:\Users\Public` (type it in, or click **Choose...** and navigate to This PC > Windows (C:) > Users > Public)
   *(GitHub Desktop appends the repo name — your final folder will be `C:\Users\Public\Demo-IaC_Demo_with_VSCode`)*
6. Click **Clone**

**Then add the upstream remote and set your fork as default** (run inside the cloned folder):

```powershell
cd "$env:PUBLIC\Demo-IaC_Demo_with_VSCode"
git remote add upstream https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode.git
git remote -v
gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode
```

<br>

---

- [ ] Folder `Demo-IaC_Demo_with_VSCode` exists in `C:\Users\Public`
- [ ] `git remote -v` shows both `origin` (your fork) and `upstream` (instructor's repo)
- [ ] `gh repo set-default` confirmed your fork as the default repo
- [ ] Open the cloned folder in VS Code: `code "$env:PUBLIC\Demo-IaC_Demo_with_VSCode"` — accept the recommended extensions prompt.

---

## 🚀 H. First deploy (L1.1) — the classroom step

This is the whole classroom setup. Everything runs in the browser:

- [ ] On GitHub — signed in as **your workshop account** — open **your fork** and click **Actions**, then the green **"I understand my workflows, go ahead and enable them"** button if prompted (forks disable workflows by default).
- [ ] Run **Curriculum L1.1 - Core Deployment** → **Run workflow** → **Run workflow**. (No inputs needed — it targets the resource group named after your account automatically.)
- [ ] Watch the **What-if** step — it lists every resource that will be created. Read it before the deploy step runs.
- [ ] Green check on all three stages (Lint → What-if → Deploy)? 🎉 Continue with the **[L1.1 guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-1-Core-Deployment)**.

---

## 🧰 Self-hosted setup (Sections E & G)

Everything below is for people running the workshop **on their own subscription**. Classroom accounts skip it entirely — see [Already done for you](#-already-done-for-you-classroom) above.

### 🍴 E. Fork the repo to your GitHub account (self-hosted)

> **Why fork and not just clone?** GitHub Actions workflows run under the repo they live in. Your fork is your personal copy with its own workflow runs and its own configuration.

From **PowerShell** in your bootstrap folder, run:

```powershell
cd "$env:PUBLIC\Demo-IaC-Bootstrap"
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
- [ ] **No `[WARN] Azure CLI was NOT validated` at the end.** Forking only needs `gh`, so the script finishes without Azure CLI — but `Setup-Oidc.ps1` in Section G will fail without it. If you see that warning, go back to Sections C and D.
- [ ] Your fork URL is shown in the terminal — copy it, you will use it in Section F

> [!NOTE]
> **Already have a repo called `Demo-IaC_Demo_with_VSCode`?** The script checks that the repo in your account is genuinely a fork *of this workshop*, not just a name match. It **warns and keeps going** rather than stopping — but read the warning, because it means the URL it prints is the wrong repo. Rename or delete that repo and re-run; otherwise every later step (`gh repo set-default`, the OIDC credential, the deploy workflows) points at a repo with none of the lab's workflows in it.

> If your environment blocks script downloads in the terminal, download `Connect-AzureAndGitHub.ps1` in a browser, save it to `C:\Users\Public\Demo-IaC-Bootstrap\`, then run it.

### 🔗 G. Wire up GitHub → Azure (OIDC, one-time — self-hosted)

> **Before running any command in this section**, move into the cloned repo folder:
> ```powershell
> cd "$env:PUBLIC\Demo-IaC_Demo_with_VSCode"
> ```
> If you see `fatal: not a git repository`, you skipped Section F — go back and clone your fork first.

This creates a passwordless identity that GitHub Actions uses to deploy to Azure. All labs deploy into your single resource group — they do not create their own.

**Create the resource group first** — the group must already exist, and no lab creates it:

```powershell
az group create --name "<your-rg>" --location eastus2
```

Then run Setup-Oidc. `-ResourceGroup` controls **where permissions are scoped**; `-Prefix` controls **unique naming** (Entra app + lab resource names).

> [!TIP]
> **Optional preview (`-WhatIf`)** — safe dry run. You should only see planned actions, with no changes applied.

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "<your-rg>" -Prefix "<yourname>" -WhatIf
```

#### Run for real

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "<your-rg>" -Prefix "<yourname>"
```

#### Verify (run this only after the script completes)

```powershell
gh secret list
gh variable list
```

- [ ] `gh secret list` shows all 6 secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`
- [ ] `gh variable list` shows `AZURE_PREFIX` and `AZURE_LOCATION`

*(This 6-secret state is self-hosted only. On a classroom fork, both commands correctly return nothing — the workflow's in-code defaults and the shared federated identity replace them.)*

> Full walkthrough and manual steps: [Deployment Guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Deployment-Guide). Instructor pre-lab setup: [Instructor Setup](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Instructor-Setup).

---

## Quick "am I ready?" self-test

| Question | Where to fix if "no" |
|---|---|
| Signed in to GitHub as my workshop account (`User<nn>-TechCon`)? *(classroom)* | Sign out and back in with the account your instructor gave you |
| My fork exists at `github.com/<me>/Demo-IaC_Demo_with_VSCode`? | Classroom: pre-created — check you are signed in as the right account. Self-hosted: Section E |
| The Actions tab shows the deploy workflows (not blocked)? | Section H — click the green enable button |
| `gh secret list` on my **classroom** fork returns `no secrets found`? | That is **correct** — nothing to fix. Fallbacks in the workflow files cover everything |
| `gh variable list` on my **classroom** fork returns nothing? | Also correct — the prefix derives from your account name automatically |
| *(Copilot/CLI path)* Local clone exists in C:\Users\Public? | Section F |
| *(Copilot/CLI path)* `git remote -v` shows both `origin` and `upstream`? | Section F |
| *(Copilot/CLI path)* `gh repo set-default` points to my fork? | Section F |
| *(Self-hosted)* `gh secret list` shows `AZURE_RESOURCE_GROUP` and 5 others? | Section G |
| *(Self-hosted)* `gh variable list` shows `AZURE_PREFIX` and `AZURE_LOCATION`? | Section G |

Stuck on any of these → [Troubleshooting](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Troubleshooting).

---

➡️ Ready? Head to **[L1.1 — Core Deployment](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-1-Core-Deployment)** and run your first deploy. The main path continues east: **L1.1 → L2.1 → L3.1 → L4.1** — see the [Curriculum Map](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Map).

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Secrets versus variables**
>
> **You just used it — by not needing it:** a classroom fork carries **no secrets and no variables at all.** The workflows read every value through a fallback expression like `${{ secrets.VM_ADMIN_PASSWORD || format('{0}!!', github.repository_owner) }}`, and authentication happens through a federated trust rather than a stored credential — so there is nothing to push into your fork. Self-hosted forks are the contrast: there `Setup-Oidc.ps1` pushes both kinds — `AZURE_PREFIX` and `AZURE_LOCATION` as **variables** (they appear in resource names and logs anyway), passwords and IDs as **secrets**.
> **Find it:** **Settings → Secrets and variables → Actions**. You can read a variable back; you can never read a secret back, only replace it. In a run log a secret prints as `***`, automatically.
> **Beyond the lab:** the test is simple — if someone leaking it would cause harm, it is a secret; if you would happily print it in a log, it is a variable. And a fallback default in the workflow file is how you make secrets *optional* without making them impossible.
> [Docs →](https://docs.github.com/actions/security-guides/using-secrets-in-github-actions)
