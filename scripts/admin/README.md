# Pre-Lab Admin Setup

This folder contains three PowerShell scripts that the **instructor** runs once before the lab begins to provision every student's environment. Students never run these scripts.

---

## Before you start

### You need

- **PowerShell 7** -- run `pwsh --version` to confirm
- **Az PowerShell module** -- run once:
  ```powershell
  Install-Module Az -Scope CurrentUser -Force
  Connect-AzAccount
  ```
- **Azure CLI** signed in: `az login`
- **GitHub CLI** signed in: `gh auth login`
- **lab-user-data.csv** placed in this folder (copy from `lab-user-data.csv.example` and fill in real values)

### Azure permissions required

| Permission | Why |
|------------|-----|
| **Owner** or **User Access Administrator** on the subscription | To create role assignments for students |
| **Resource Policy Contributor** or Owner on each resource group | To assign Azure Policy |
| **Application Administrator** in Entra ID | To create app registrations for OIDC (only if tenant restricts it; most tenants allow it by default) |

### GitHub permissions required

| Permission | Why |
|------------|-----|
| **Admin** on each student's GitHub fork | To push secrets and variables via `gh secret set` |

---

## Step 1 -- Fill in lab-user-data.csv

Copy `lab-user-data.csv.example` to `lab-user-data.csv` in **this same folder** and fill in the real values.

> **Important:** `lab-user-data.csv` is in `.gitignore` and will never be committed to the repo. It contains passwords. Keep it local.

### Required CSV columns

| Column | What to enter |
|--------|---------------|
| `Entra ID Username` | Full UPN -- e.g. `Student140801@npluslab.onmicrosoft.com` |
| `Type` | `Instructor` for the instructor row; `Student` for everyone else |
| `SubscriptionId` | Azure subscription GUID -- same value on every row |
| `Event` | Tag value for the event name -- e.g. `TechConn` |
| `GitHub Username` | Student's GitHub login email (the UPN prefix is used as the GitHub handle) |
| `TAP` / `Entra Password` / `GH Password` | Fill in as provided -- not consumed by these scripts |

---

## Step 2 -- Run the three scripts in order

**Always run with `-WhatIf` first to preview every action before it happens.**

### Script 1: New-LabEnvironment.ps1

Creates one resource group per student, applies four required tags, and sets RBAC.

```powershell
# Preview first -- no changes made
./New-LabEnvironment.ps1 -WhatIf

# Apply for real
./New-LabEnvironment.ps1

# Also create User Assigned Managed Identities per student (optional)
./New-LabEnvironment.ps1 -IncludeManagedIdentity
```

What it creates per student:
- Resource group: `rg-techdemo-<username>`
- Tags on the RG: `Owner`, `Event`, `Date`, `Instructor`
- Student gets **Contributor** on their own RG
- Instructor gets **Contributor** on all student RGs

---

### Script 2: Set-LabPolicy.ps1

Applies Azure Policy guardrails to every `rg-techdemo-*` resource group.

```powershell
# Preview
./Set-LabPolicy.ps1 -WhatIf

# Apply
./Set-LabPolicy.ps1
```

What it assigns per resource group (6 policy assignments):
- Deployments restricted to **eastus2** only
- Only resource types used by the labs are allowed
- Four tag inheritance rules: `Owner`, `Event`, `Date`, `Instructor` automatically copy from RG to every resource created inside it

---

### Script 3: Setup-OidcAll.ps1

Wires up GitHub Actions -> Azure authentication for every student at once.

```powershell
# Preview
./Setup-OidcAll.ps1 -WhatIf

# Apply
./Setup-OidcAll.ps1
```

What it creates per student:
- Entra app registration: `iac-demo-stu<number>`
- Service principal and federated credential (passwordless OIDC)
- Contributor role on their resource group for the service principal
- Six **GitHub secrets** pushed to their fork: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`
- Two **GitHub variables** pushed: `AZURE_PREFIX`, `AZURE_LOCATION`

> After this script finishes, students run `gh secret list` on their fork and see all six secrets. They skip directly to **Section G -- Step 3 (Verify)** in the lab checklist.

---

## What students experience after you run all three

| Section G step | Without admin setup | After admin setup |
|----------------|--------------------|--------------------|
| Step 1 -- Check | `gh secret list` returns empty | `gh secret list` shows 6 secrets |
| Step 2 -- Run Setup-Oidc | Student runs the script themselves | **SKIP -- already done** |
| Step 3 -- Verify | Run after Step 2 | Run immediately |

---

## Re-running is safe

All three scripts are **idempotent** -- existing resources, role assignments, and policy assignments are detected and skipped. Re-run at any time to repair a failed step or add a student.

---

## Files in this folder

| File | Purpose |
|------|---------|
| `New-LabEnvironment.ps1` | Provision resource groups, tags, and RBAC |
| `Set-LabPolicy.ps1` | Apply Azure Policy guardrails |
| `Setup-OidcAll.ps1` | Bulk OIDC wiring (GitHub -> Azure) |
| `lab-user-data.csv.example` | Template -- copy this and fill in real values |
| `lab-user-data.csv` | Your real data -- never committed (in `.gitignore`) |
| `.gitkeep` | Keeps the folder tracked in git when CSV is absent |
