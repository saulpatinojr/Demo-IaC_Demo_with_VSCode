# Instructor Setup Guide

This page covers everything you need to do **before** participants arrive, plus the exact permissions to grant in both GitHub and Azure. Students have no sub-level permissions — each gets exactly **one pre-created resource group** and **Contributor on it**.

---

## 0. 🤖 Automated pre-lab setup (run these first)

Two scripts in `scripts/admin/` handle all bulk provisioning. Run them in order before participants arrive.

> [!IMPORTANT]
> Both scripts require the **Az PowerShell module**. Install it once:
> ```powershell
> Install-Module Az -Scope CurrentUser -Force
> Connect-AzAccount
> ```
> The account must have **Owner or User Access Administrator** on the subscription to create role assignments.

### Step 0A — Provision all student environments

Place `lab-user-data.csv` (the student roster exported from your Entra/GitHub admin tool) in the **`scripts/admin/`** folder alongside this script. The script auto-detects the instructor from the `Type = Instructor` row — no hardcoded names.

```powershell
# Preview first -- no changes made
./scripts/admin/New-LabEnvironment.ps1 -WhatIf

# Apply for real (add -IncludeManagedIdentity to also create UAMIs)
./scripts/admin/New-LabEnvironment.ps1 -IncludeManagedIdentity
```

> [!NOTE]
> The real `lab-user-data.csv` is listed in `.gitignore` — it is never committed to the repo. Copy `lab-user-data.csv.example` as a template. Only the `.example` file is tracked.

This script creates **31 resource groups** (`rg-techdemo-Student140801` … `rg-techdemo-Saul.Patina`), applies 4 required tags to each, assigns students Contributor on their own RG, and assigns the instructor Contributor on all RGs.

**Tags applied to every resource group:**

| Tag | Value |
|-----|-------|
| `Owner` | Username (before `@`) of the student |
| `Event` | Value from the CSV `Event` column |
| `Date` | UTC date the script ran (`yyyy-MM-dd`) |
| `Instructor` | Username (before `@`) of the instructor |

### Step 0B — Apply Azure Policy guardrails

```powershell
# Preview
./scripts/admin/Set-LabPolicy.ps1 `
    -SubscriptionId "<your-subscription-id>" `
    -WhatIf

# Apply
./scripts/admin/Set-LabPolicy.ps1 `
    -SubscriptionId "<your-subscription-id>"
```

This assigns **6 Azure Policy assignments** to every `rg-techdemo-*` resource group:
- **Allowed locations** — only `eastus2` deployments are permitted
- **Allowed resource types** — only the ~38 resource types used by L1–L4 are permitted
- **Inherit tag × 4** — `Owner`, `Event`, `Date`, `Instructor` automatically propagate from the RG to every resource deployed inside it

> [!NOTE]
> Policy assignments take effect within a few minutes. New resources that violate the policy are blocked at deployment time with a clear error message.

### Step 0C — Pre-wire OIDC for all students (recommended)

This step is **optional but strongly recommended** for classroom labs. When the instructor runs this, students land directly on **Section G → Step 3 (Verify)** — they never need to run `Setup-Oidc.ps1` themselves.

```powershell
# Preview
./scripts/admin/Setup-OidcAll.ps1 -WhatIf

# Apply
./scripts/admin/Setup-OidcAll.ps1
```

This script loops over every Student row in the CSV and for each one:
- Creates an Entra app registration (`iac-demo-<prefix>`) + service principal
- Adds federated credentials for the student's fork (`main` branch + pull requests)
- Grants Contributor on their resource group
- Pushes all 6 required GitHub secrets and 2 variables to the student's fork

> [!IMPORTANT]
> Your `gh` account must have **Admin access** to each student's fork to push secrets. In a shared GitHub org, org admins have this automatically. For personal forks, you must be a collaborator with Admin role on each repo.
> 
> Students' GitHub handles are derived from their Entra UPN prefix (e.g. `Student140801@domain.com` → handle `Student140801`). Fork URL becomes `Student140801/Demo-IaC_Demo_with_VSCode`.

**Instructor order of operations:**
1. `New-LabEnvironment.ps1` — create all RGs
2. `Set-LabPolicy.ps1` — apply policy guardrails
3. `Setup-OidcAll.ps1` — wire OIDC for all students *(this step)*
4. Students then go directly to **Section G → Step 3** (skip Steps 1 and 2)

---

## 🧾 Overview: what you provision per participant

| Item | What it is | Who creates it |
|------|-----------|----------------|
| GitHub org membership | Participant can fork and use Actions | Instructor (invite) |
| GitHub Copilot seat | Required for Copilot agent mode | Instructor (assign) |
| Azure resource group | e.g. `rg-lab-alice` | Instructor |
| Contributor on RG | Lets the participant deploy resources | Instructor |
| Owner (or RBAC Admin) on RG | Lets the OIDC setup script grant Contributor to the service principal | Instructor, **OR** instructor runs setup on the student's behalf |
| Entra app registration (optional) | The OIDC identity; can be student-created or instructor-created | Instructor or student (see below) |

---

## 1. 🐙 GitHub Organization Permissions

### What participants need

| Permission | How to grant | Notes |
|-----------|-------------|-------|
| **Org membership** | Invite them at `github.com/<org>/people` | Role: **Member** is enough |
| **Fork the lab repo** | Org Settings → Member privileges → *Allow forking of repositories* → **Enabled** | Without this, students cannot get their own copy |
| **GitHub Actions on forks** | Org Settings → Actions → General → *Allow all actions and reusable workflows* | On first run, Actions on a forked public repo require a one-time approval click — walk participants through this |
| **Copilot license** | Org Settings → Copilot → *Access* → add member | **Business** or **Enterprise** required; Free tier also works for individuals |
| **Secrets & variables (their fork)** | Automatic | Participants own their fork, so they have Admin rights on it |

### Org-level settings checklist

```
GitHub → <org> → Settings → Actions → General
  ✅  Allow all actions and reusable workflows
  ✅  Allow GitHub Actions to create and approve pull requests (optional, not required)

GitHub → <org> → Settings → Member privileges
  ✅  Allow forking of repositories

GitHub → <org> → Settings → Copilot
  ✅  Copilot seats assigned to all participants
```

> **Private repo?** If you made the lab repo private in the org, participants will need at least **Read** access to it so they can fork it. Grant via `<repo> → Settings → Collaborators and teams`.

---

## 2. ☁️ Azure Permissions

### Summary: what each participant's OIDC service principal needs

The `scripts/Setup-Oidc.ps1` script creates an **Entra app registration + service principal** and grants it **Contributor** on the participant's resource group. Those two actions require different permissions:

| Action | Required Azure role |
|--------|-------------------|
| `az ad app create` (Entra app registration) | **Application Developer** (or any role that allows app registration) in Entra ID. By default, all tenant users can register apps — check your tenant. |
| `az role assignment create` (grant Contributor to the SP) | **Owner** or **Role Based Access Control Administrator** on the resource group. **Contributor alone is not enough.** |

### Recommended path: instructor runs setup, student deploys

This avoids giving participants elevated RBAC rights and works regardless of tenant app-registration policies.

**Instructor does (once per participant):**

```powershell
# 1. Create the resource group
az group create --name rg-lab-<prefix> --location eastus2

# 2. Run the OIDC setup on the participant's behalf (signed in as instructor)
./scripts/Setup-Oidc.ps1 `
    -GitHubRepo "<orgOrUser>/Demo-IaC_Demo_with_VSCode" `
    -ResourceGroup "rg-lab-<prefix>" `
    -Prefix "<prefix>" `
    -Location "eastus2" `
    -AlertEmail "<participant-email>"
# This creates: iac-demo-<prefix> Entra app, federated credential, Contributor on RG,
# and pushes all secrets + variables to the participant's fork.

# 3. Grant the participant ONLY Contributor on their RG (not RBAC admin):
STUDENT_OID=$(az ad user show --id <participant-upn-or-email> --query id -o tsv)
az role assignment create \
  --assignee-object-id $STUDENT_OID \
  --assignee-principal-type User \
  --role Contributor \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-lab-<prefix>
```

After step 2, the participant only needs to **sign in with `az login` and `gh auth login`** — no extra setup required.

### Alternative path: student runs setup themselves

If your tenant allows app registration (default) and you grant participants Owner on their RG:

```powershell
# Grant Owner on their RG (instead of just Contributor):
az role assignment create \
  --assignee <student-email-or-object-id> \
  --role Owner \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-lab-<prefix>
```

The student then runs `Setup-Oidc.ps1` themselves, which creates their own app registration and sets up the federated credential.

### Azure roles summary

| Who | Scope | Required role |
|-----|-------|--------------|
| **Instructor** (running setup) | Subscription | **Contributor** (to create RGs) + **User Access Administrator** (to grant roles) — OR **Owner** covers both |
| **Instructor** (Entra) | Tenant | **Application Administrator** or **Global Administrator** (only if tenant restricts app registration) |
| **Participant** (classroom mode) | Their resource group | **Contributor** |
| **OIDC service principal** (`iac-demo-<prefix>`) | Their resource group | **Contributor** (granted by the setup script) |

### Entra app registration tenant setting

Check whether your tenant allows all users to register apps:

```
Azure Portal → Entra ID → Users → User settings →
  "Users can register applications" → Yes (default) or No (restricted)
```

If **No**, you must either:
- Grant participants the **Application Developer** Entra role, OR
- Run `Setup-Oidc.ps1` as an instructor (Application Administrator) and share the resulting secrets

---

## 3. ✅ Per-Participant Setup Checklist

Run this for each participant before the lab. Replace `<prefix>` with their unique short identifier (initials, first name, etc., max 12 characters).

```
PARTICIPANT:  <name>
PREFIX:       <prefix>        ← must be unique, ≤12 chars, alphanumeric
GITHUB FORK:  <orgOrUser>/Demo-IaC_Demo_with_VSCode
RESOURCE GROUP: rg-lab-<prefix>
REGION:       eastus2
```

**GitHub (5 min)**
- [ ] Invite to org → org Member
- [ ] Assign Copilot seat
- [ ] Confirm participant has forked the repo
- [ ] Confirm participant has enabled Actions on their fork (first-time approval)

**Azure (10 min)**
- [ ] `az group create --name rg-lab-<prefix> --location eastus2`
- [ ] `./scripts/Setup-Oidc.ps1 -GitHubRepo "<fork>" -ResourceGroup "rg-lab-<prefix>" -Prefix "<prefix>" -AlertEmail "<email>"`
- [ ] Verify secrets pushed: `gh secret list --repo <fork>`
- [ ] Verify variables pushed: `gh variable list --repo <fork>`
- [ ] Confirm Contributor assignment: `az role assignment list --scope /subscriptions/<sub>/resourceGroups/rg-lab-<prefix> --role Contributor -o table`

**Participant self-check (before starting)**
- [ ] `az login` → correct subscription shows
- [ ] `gh auth status` → logged in
- [ ] Actions tab → workflows visible (not disabled)
- [ ] `gh secret list` → shows `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`
- [ ] `gh variable list` → shows `AZURE_PREFIX`, `AZURE_LOCATION`

---

## 4. 🔤 Naming Conventions & Collision Prevention

All resource names in this lab are derived from `AZURE_PREFIX`. Choosing **unique prefixes** prevents naming conflicts in the shared subscription.

| Example prefix | Entra app name | Hub VNet | SQL server (L3) |
|---------------|---------------|----------|-----------------|
| `alice` | `iac-demo-alice` | `vnet-alice-hub` | `sql-alice-<hash>` |
| `bob` | `iac-demo-bob` | `vnet-bob-hub` | `sql-bob-<hash>` |

**Rules for prefixes:**
- Max 12 characters (enforced by `@maxLength(12)` in Bicep)
- Alphanumeric + hyphens only
- Must be unique across all participants in the same subscription

Suggested convention: first name or initials, e.g. `alice`, `jsmith`, `team1`.

> Some resources (Azure SQL, Key Vault) require globally unique names. The Bicep templates use `uniqueString(subscription().id, prefix)` to generate a stable 6-char suffix — this is unique per subscription+prefix combination, which is sufficient as long as all students are in the same subscription with different prefixes.

---

## 5. 💲 Cost & Quota

### Per-participant cost estimate (while resources are running)

| Lab | Key billable resources | Approx. hourly cost |
|-----|----------------------|---------------------|
| L1 | 1× Bastion Basic, 1× B2s VM | ~$0.25/hr |
| L2 | + Azure Firewall Standard | +$1.25/hr |
| L3 | + Container Apps, SQL Basic, Key Vault | +$0.10/hr |
| L4 | + Front Door Standard, 1× secondary Container App | +$0.05/hr |

**Azure Firewall and Bastion are the cost drivers.** For a 4-hour lab with 20 participants all at L2: ~20 × $1.50 × 4 = **~$120**.

### Quota to check before the lab

Run these in the subscription:

```bash
# VM cores (Standard_B family)
az vm list-usage -l eastus2 --query "[?contains(name.value,'standardBSFamily')]" -o table

# Public IP addresses
az network list-usages -l eastus2 --query "[?name.value=='PublicIPAddresses']" -o table

# Container Apps environments
az containerapp env list -o table
```

Check the output to confirm the selected region has available capacity.

Each student at L2 uses: ~4 B2s cores, 1 Firewall, 1 Bastion, 1 PIP.
Each student at L3 uses: 1 Container Apps environment, 1 SQL server, 1 Key Vault.
Each student at L4 uses: 1 additional Container Apps environment + 1 SQL server in `westus2` + 1 Front Door.

### Cleanup after the lab

```powershell
# Per student (classroom mode — deletes resources, not the RG):
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-<prefix>"

# Instructor: delete the RG entirely when the lab is fully done:
az group delete --name rg-lab-<prefix> --yes

# Remove the OIDC app registration:
./scripts/Cleanup-Labs.ps1 -Prefix "<prefix>" -RemoveOidc
```

---

## 6. 🛟 Troubleshooting Common Instructor Issues

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `AADSTS700213: No matching federated identity record found` | Federated credential subject doesn't match the fork's owner/repo/branch | Re-run `Setup-Oidc.ps1` with the correct `-GitHubRepo` value |
| Workflow fails: `Missing repo secret 'AZURE_RESOURCE_GROUP'` | Student's fork didn't receive the secret | Re-run `Setup-Oidc.ps1 -ResourceGroup ...` targeting the student's fork |
| `az role assignment create` fails with `AuthorizationFailed` | Instructor account lacks Owner/RBAC-Admin on the scope | Check your role at the RG scope: `az role assignment list --scope <rg-id> --assignee <you> -o table` |
| Students' Actions are blocked on first run | Fork's Actions require one-time approval | Walk them through: Actions tab → "I understand my workflows, go ahead and enable them" |
| Two students' resource names clash | Same prefix used | Re-run setup for one student with a different prefix, update their `AZURE_PREFIX` variable |
| Bicep deployment fails: `ResourceGroupNotFound` | `AZURE_RESOURCE_GROUP` secret is wrong or RG wasn't created | Verify: `az group show --name <rg>` and check the secret value in GitHub |

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · One fork per participant**
>
> **You just used it:** the model you are provisioning gives every student their own fork, and therefore their own Actions runs, their own secrets and their own blast radius. Nobody can break anyone else's lab.
> **Find it:** each student's repo at `github.com/<their-handle>/Demo-IaC_Demo_with_VSCode`. Their OIDC subject names *their* fork, so their credential only works from it.
> **Beyond the lab:** this is why the classroom scales. Twenty students need no coordination, no shared branch and no queue — and a mistake stays inside one fork.
> [Docs →](https://docs.github.com/pull-requests/collaborating-with-pull-requests/working-with-forks/about-forks)
