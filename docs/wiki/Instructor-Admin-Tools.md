# Instructor Admin Tools

> These tools are for the **instructor only**. Students never run anything in the `scripts/admin/` folder.

Three PowerShell scripts pre-configure every student's environment before the lab begins. When all three are done, students pick up the checklist at **Section G -- Step 3 (Verify)** -- no OIDC setup, no role hunting, no confusion.

---

## 🗺️ Overview -- what the three scripts do

<table>
<tr>
<td align="center" width="220"><strong>1. New-LabEnvironment</strong><br><sub>Resource groups + RBAC</sub></td>
<td align="center" width="220"><strong>2. Set-LabPolicy</strong><br><sub>Azure Policy guardrails</sub></td>
<td align="center" width="220"><strong>3. Setup-OidcAll</strong><br><sub>GitHub &lt;-&gt; Azure OIDC</sub></td>
</tr>
</table>

Run them in that order. Each script is idempotent -- re-running repairs without duplicating.

---

## 🗂️ The CSV file -- your single source of truth

All three scripts read their configuration from `lab-user-data.csv` placed in the **`scripts/admin/`** folder alongside the scripts. There are no hardcoded values and no parameters to memorize.

> [!IMPORTANT]
> `lab-user-data.csv` contains credentials. It is listed in `.gitignore` and is **never committed** to the repo. Copy `lab-user-data.csv.example`, fill it in, and keep it local.

### Required columns

| Column | Who fills it | Example value |
|--------|-------------|---------------|
| `Entra ID Username` | Instructor | `Student140801@npluslab.onmicrosoft.com` |
| `Type` | Instructor | `Instructor` or `Student` |
| `SubscriptionId` | Instructor | `a66afdab-e353-4499-b148-bf42c65b562b` |
| `Event` | Instructor | `TechConn` |
| `GitHub Username` | Instructor | Same as Entra UPN (GitHub handle = UPN prefix) |
| `TAP` / `Entra Password` / `GH Password` | Admin team | Provided by Entra/GitHub admin export |

The scripts auto-detect the instructor from the `Type = Instructor` row. They read `SubscriptionId` and `Event` from the CSV -- no values need to be passed as parameters.

---

## 🔧 Prerequisites

> [!IMPORTANT]
> Install the Az PowerShell module once before running any of these scripts:
> ```powershell
> Install-Module Az -Scope CurrentUser -Force
> Connect-AzAccount   # signs in to Azure (Az PowerShell)
> az login            # signs in to Azure (Az CLI -- needed by Setup-OidcAll)
> gh auth login       # signs in to GitHub (needed by Setup-OidcAll)
> ```

### Azure permissions needed

| Role | Where | Needed for |
|------|-------|-----------|
| **Owner** or **User Access Administrator** | Subscription | Creating role assignments (RBAC) |
| **Resource Policy Contributor** or Owner | Each resource group | Assigning Azure Policy |
| **Application Administrator** (Entra) | Tenant | Creating Entra app registrations for OIDC |

### GitHub permissions needed

Your `gh` account must have **Admin** access to each student's GitHub fork to push secrets and variables.

> [!TIP]
> In a shared GitHub org, org admins automatically have Admin access to all forks within the org. For personal forks, add the instructor as a collaborator with Admin role.

---

## 1. ⚙️ New-LabEnvironment.ps1 -- Provision all student environments

**What it does** per student row in the CSV:
- Creates resource group `rg-techdemo-<username>` in the target location
- Applies four required tags to the RG
- Assigns the student **Contributor** on their own RG
- Assigns the instructor **Contributor** on all student RGs
- *(Optional)* Creates a User Assigned Managed Identity `<username>-mi` and grants it Contributor

**Tags applied to every resource group:**

| Tag | Value | Where it comes from |
|-----|-------|---------------------|
| `Owner` | UPN prefix of the student | Derived from CSV |
| `Event` | Event name | CSV `Event` column |
| `Date` | Today's UTC date | Auto-generated |
| `Instructor` | UPN prefix of the instructor | Derived from CSV |

**Run it:**

```powershell
# Always preview first
./scripts/admin/New-LabEnvironment.ps1 -WhatIf

# Apply for real
./scripts/admin/New-LabEnvironment.ps1

# Include User Assigned Managed Identities (optional)
./scripts/admin/New-LabEnvironment.ps1 -IncludeManagedIdentity
```

> [!NOTE]
> Role assignments use a retry loop (up to 5 attempts, 10 seconds apart) to handle Entra propagation lag when accounts are freshly created. You will see `[warn] ... retrying` messages -- this is normal.

---

## 2. 🛡️ Set-LabPolicy.ps1 -- Apply Azure Policy guardrails

**What it does** -- assigns 6 Azure Policy assignments to every `rg-techdemo-*` resource group:

| # | Policy | Effect |
|---|--------|--------|
| 1 | Allowed locations | Only `eastus2` deployments are permitted |
| 2 | Allowed resource types | Only ~38 types used by L1-L4 labs are allowed |
| 3 | Inherit tag: Owner | Every resource inside the RG inherits the `Owner` tag |
| 4 | Inherit tag: Event | Every resource inherits the `Event` tag |
| 5 | Inherit tag: Date | Every resource inherits the `Date` tag |
| 6 | Inherit tag: Instructor | Every resource inherits the `Instructor` tag |

**Run it:**

```powershell
# Always preview first
./scripts/admin/Set-LabPolicy.ps1 -WhatIf

# Apply
./scripts/admin/Set-LabPolicy.ps1
```

> [!NOTE]
> Policy assignments take a few minutes to take effect. Resources that violate the policy will be blocked at deploy time with a clear error message -- not silently.

---

## 3. 🔗 Setup-OidcAll.ps1 -- Bulk OIDC wiring

**What it does** per student row in the CSV:
- Creates Entra app registration `iac-demo-stu<number>` (or reuses if it exists)
- Creates service principal and two federated credentials (main branch + pull requests)
- Grants the service principal **Contributor** on the student's resource group
- Pushes 6 **GitHub secrets** to the student's fork: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`
- Pushes 2 **GitHub variables**: `AZURE_PREFIX`, `AZURE_LOCATION`

**Run it:**

```powershell
# Always preview first
./scripts/admin/Setup-OidcAll.ps1 -WhatIf

# Apply
./scripts/admin/Setup-OidcAll.ps1
```

> [!TIP]
> The `AZURE_PREFIX` variable is derived as `stu<number>` from the student's UPN (e.g. `Student140801` becomes `stu140801`). This keeps it under Bicep's 12-character limit on resource name prefixes.

> [!NOTE]
> Re-running this script rotates the VM and SQL throwaway passwords. It is safe to re-run.

---

## ✅ What students experience after you run all three

Once all three scripts complete, students only need to:

1. Fork the repo (Section E)
2. Clone their fork (Section F)
3. Jump straight to **Section G -- Step 3 (Verify)**

```powershell
# Student runs this -- should immediately show 6 secrets
gh secret list
```

| What they see | What it means |
|---------------|---------------|
| A list of 6 secret names | Instructor pre-ran Setup-OidcAll -- student skips to Step 3 |
| `no secrets found` | Instructor did not run Setup-OidcAll -- student runs Step 2 themselves |

---

## 🔄 Re-running and idempotency

All three scripts check before acting:

- Existing resource groups are detected (tags are merged, not overwritten)
- Existing role assignments are skipped
- Existing policy assignments are skipped
- Existing Entra apps and federated credentials are reused
- Existing GitHub secrets are overwritten (secrets are write-only -- this is intentional)

---

## 🛟 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Cannot switch to subscription 'xxx'` | SubscriptionId in CSV is wrong or you lack access | Verify the GUID in the CSV and that `az account list` shows this subscription |
| `Not signed in to Azure` | `Connect-AzAccount` or `az login` not done | Run `Connect-AzAccount` and `az login` |
| `Could not set secret on fork` | Your `gh` account lacks Admin on the student's fork | Add your GitHub account as a collaborator with Admin role, or run as org admin |
| `Role assignment failed after 5 attempts` | Entra propagation lag beyond 50 seconds | Re-run the script -- it will skip already-assigned roles and retry the failed one |
| Policy assignment fails with `AuthorizationFailed` | Missing Resource Policy Contributor or Owner on the RG | Check your Azure role at the RG scope |

---

*Full instructor pre-lab guide including GitHub org settings: [Instructor Setup Guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Instructor-Setup)*
