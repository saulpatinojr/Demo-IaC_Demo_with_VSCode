# Troubleshooting

> [!TIP]
> **Most classroom failures are one of three things:** (a) you are signed in as the wrong GitHub account or running from the wrong fork, (b) workflows are not yet enabled on your fork (Actions tab → green button), or (c) an instructor-side identity problem — report it, don't try to fix it. And remember: **`gh secret list` returning `no secrets found` is NOT a problem** — classroom forks need zero secrets; the workflows carry in-code defaults for everything.

---

## 🔐 OIDC and login failures

**Classroom first:** the workflow targets the resource group named after the fork owner, authenticates through a shared identity federated to your fork, and needs no secrets. So before anything else, check three things: signed in as `User<nn>-TechCon`? On **your** fork (`github.com/<your-account>/Demo-IaC_Demo_with_VSCode`)? Workflows enabled?

| Symptom | Cause and fix |
|---------|--------------|
| `AADSTS700213: No matching federated identity record` | The federated credential `subject` on the deploy identity does not match the repo the run came from. **Classroom:** this is an instructor/admin problem on the shared identity — first confirm you ran the workflow from *your* fork while signed in as your workshop account; if so, **report it to your instructor** (instructors/admins: see [FIX-STUDENT-DEPLOYMENTS.md](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/FIX-STUDENT-DEPLOYMENTS.md)). **Self-hosted:** the subject must be exactly `repo:<user>/Demo-IaC_Demo_with_VSCode:ref:refs/heads/main` — re-run `Setup-Oidc.ps1` to recreate it. |
| Deploy targets a resource group that is not your account name | The workflow defaults the target group to the **fork owner's name**. If the RG in the error is not your account name, you are running from the wrong fork or signed in as the wrong account. Open `github.com/<your-account>/Demo-IaC_Demo_with_VSCode` → Actions and run from there. |
| `Resource group '<name>' does not exist in subscription` | **Classroom:** your group is pre-created and named exactly like your GitHub account — if the name in the error differs, wrong fork/account (see the row above); if it matches and still fails, report to your instructor. **Self-hosted:** no lab creates the group — `az group create --name "<your-rg>" --location eastus2` first, and don't type a placeholder literally. |
| `AuthorizationFailed` during deploy | The deploy identity lacks Contributor on the target group. **Classroom:** if you are on the right fork/account, this is instructor-side — report it. **Self-hosted:** re-run `Setup-Oidc.ps1 -ResourceGroup "<your-rg>"`. |
| `AADSTS70021` / audience errors | The federated credential's `audiences` field must be `api://AzureADTokenExchange`. **Classroom:** instructor-side — report it. **Self-hosted:** re-run the setup script. |
| VM or SQL deploy fails on password validation | **Classroom:** the default password is `<your-account>!!` (e.g. `User01-TechCon!!`), which satisfies Azure's rules — if you set a `VM_ADMIN_PASSWORD`/`SQL_ADMIN_PASSWORD` secret yourself, it overrides the default and must meet the rules (12+ chars, 3 of 4 character classes, no username inside). Delete the bad secret to fall back to the default. **Self-hosted:** re-run `Setup-Oidc.ps1` to regenerate compliant passwords. |
| Workflow doesn't appear / won't run | Workflows are disabled on forks by default. On **your** fork: Actions tab → green **"I understand my workflows, go ahead and enable them"** button. |
| Login step fails with "id-token: write" hint | The workflow's `permissions:` block is missing or was removed. Do not remove it when editing workflows with Copilot. |

### Self-hosted only

| Symptom | Cause and fix |
|---------|--------------|
| `ResourceGroup is required (also under -WhatIf)` from `Setup-Oidc.ps1` | You ran it without `-ResourceGroup`. It is required on every run. Create the group first if needed: `az group create --name "<your-rg>" --location eastus2`. |
| A workflow uses the wrong values after you set secrets | Fork secrets and variables always **override** the in-code classroom fallbacks — check `gh secret list` / `gh variable list` for a stale value and re-run `Setup-Oidc.ps1` to refresh the identity and resource-group secrets. |

---

## 🧭 `gh` command issues (multiple remotes / wrong repo)

| Symptom | Cause and fix |
|---------|--------------|
| `gh secret list` returns `! Multiple remotes detected. Requiring disambiguation.` | Your repo has both `origin` (your fork) and `upstream` (instructor) remotes. `gh` doesn't know which one to use. Fix: run `gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode` once inside the repo folder. |
| `gh secret list` returns `no secrets found` on a **classroom** fork | **Expected and correct** — classroom forks need no secrets. The workflows resolve everything through in-code defaults (resource group ← your account name, prefix ← derived from it, passwords ← `<account>!!`) plus the shared federated identity. Nothing to fix. |
| `gh secret list` returns `no secrets found` on a **self-hosted** fork | `Setup-Oidc.ps1` has not been run yet for this fork. Go to the self-hosted section of [Start Here Checklist — Part 2](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist-Part-2) and run the script. |
| Any `gh` command targets the wrong repo | Run `gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode` from inside the cloned folder. To verify: `gh repo view --json nameWithOwner -q .nameWithOwner`. |

---

## 🧱 Bicep and AVM

| Symptom | Cause and fix |
|---------|--------------|
| `BCP192: unable to restore br/public:avm/...` | No network path to `mcr.microsoft.com` (proxy or firewall). Run `az bicep restore --file <file>` to see details. |
| `BCP037: property not allowed` after editing | AVM module parameters differ between versions. Keep the pinned version from the ref and check the module docs: `https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/...` |
| What-if shows unexpected deletions | You renamed a resource — ARM sees a delete + create. Names are identity; rename carefully. |
| `ResourceGroupNotFound` | **Classroom:** the workflow targets the group named after the fork owner — if the name in the error isn't your account name, you're on the wrong fork/account. **Self-hosted:** the `AZURE_RESOURCE_GROUP` secret is wrong or the group was never created. Check: `az group show --name <name>`. |
| Local `az deployment group create` fails with authorization errors | **Classroom accounts hold Reader** — local deploys are expected to fail. Deploy through the Actions workflow instead. (`az bicep build` works fine locally for everyone — no Azure auth needed.) |

---

## 🧪 Lab-specific issues

| Symptom | Cause and fix |
|---------|--------------|
| **L1.1**: VM deploy fails on password | Must be 12+ characters with 3 of 4 character classes (uppercase, lowercase, digit, symbol) and must not contain the username. **Classroom:** the `<account>!!` default complies — if you overrode it with a secret, delete the secret. **Self-hosted:** re-run `Setup-Oidc.ps1` to regenerate. |
| **L1.2**: `curl http://<fw-ip>` times out | Firewall provisioning takes ~10 minutes *after* the workflow reports success. Also confirm the DNAT rule exists: `az network firewall nat-rule collection list -g <rg> -f afw-<prefix>-hub`. |
| **L1.2**: Web VMs unhealthy in the load balancer | `cloud-init` needs outbound HTTP (port 80) to install nginx. If the egress rule was tightened to HTTPS-only *before* first deploy, `apt-get` failed silently. Redeploy or loosen the rule first. |
| **L1.2**: Everything broke after adding a public LB | Asymmetric routing — inbound via public LB, return path via firewall. Use the DNAT + internal LB pattern already in the template. See the design note in the [L1.2 guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-2-Architecture-Expansion). |
| **L1.3**: Connecting to SQL from your laptop fails | That is correct and expected — public access is disabled. SQL is only reachable from inside the VNet via private endpoint. |
| **L1.3**: Container cannot reach SQL by name | The private DNS zone is linked to spoke2 only. To link another VNet: `az network private-dns link vnet create -g <rg> -z "privatelink.database.windows.net" -n <link-name> -v <vnet-id> -e false`. |
| **L1.3**: SQL or Key Vault name already taken | These names are globally unique. The template appends a `uniqueString` suffix per subscription+prefix — collisions mean someone else used the same prefix. Classroom prefixes derive from your unique account name, so this points at a duplicated `AZURE_PREFIX` variable — remove or change it. |
| **L1.4**: Front Door returns 502 or 404 at first | Origin propagation takes up to ~10 minutes after creation. Check origin health: Portal → Front Door → Origin groups → health status. |
| **L1.4**: Failover group creation fails | `SQL_ADMIN_PASSWORD` must match L1.3's exactly, and L1.3 must be fully deployed (database `sqldb-<prefix>-app` must exist on the primary server). In the classroom both labs use the same `<account>!!` default automatically. |
| Quota / SKU not available in region | `az vm list-skus -l eastus2 --size Standard_B2s -o table`. **Classroom:** report to your instructor. **Self-hosted:** pick a different region and use it consistently for ALL labs via the `-Location` flag in `Setup-Oidc.ps1`. |

---

## ⚙️ Lab settings and environment variables (self-hosted / CLI path)

| Symptom | Cause and fix |
|---------|--------------|
| Terminal commands fail with `$env:AZURE_RESOURCE_GROUP` empty | Run `./scripts/Load-LabSettings.ps1` (or `Load-LabSettings.ps1 -Persist` once to save permanently). |
| `lab-settings.csv not found` | Copy the example file: `Copy-Item lab-settings.csv.example lab-settings.csv`, then fill in your values. (Self-hosted tool — classroom accounts don't need it.) |

---

## 🤖 Copilot agent mode

- **Agent made a change that does not compile** → tell it: *"Run `az bicep build` on the file and fix the errors."* It iterates.
- **Agent cannot run `az`** → make sure Azure CLI is installed and you are logged in within the same terminal profile that VS Code uses. (Classroom accounts: the agent can build and lint, but local deploys fail under Reader — run the workflow instead.)
- **Suggestions use old API versions or non-AVM resources** → say: *"Use the pinned AVM module versions already used in this repo."*
- **Agent edited the wrong file** → undo with `Ctrl+Z` or Source Control → discard changes, then re-prompt with the specific file path.

---

## 🔍 Getting deployment details from the CLI

Reading deployment history needs only **Reader** — these work for classroom accounts too (replace `$RG` with your account-named group if the env var isn't set):

```powershell
# See the error from the last deployment in your resource group
$RG = $env:AZURE_RESOURCE_GROUP
az deployment group list -g $RG --query "[?properties.provisioningState=='Failed'].[name]" -o tsv

# Get the full error for a specific deployment
az deployment group show -g $RG --name <deployment-name> --query properties.error

# List failed operations within a deployment
az deployment operation group list -g $RG --name <deployment-name> `
  --query "[?properties.provisioningState=='Failed']"
```

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Re-running a failed job**
>
> **You just used it:** when a deploy fails, you do not have to start over. A transient Azure error, or a wrong account you have just corrected, only needs the failed part to run again.
> **Find it:** open the failed run in the **Actions** tab → **Re-run jobs** → *Re-run failed jobs*. Use **Download log archive** on the same menu to grab the full output for a bug report.
> **Beyond the lab:** re-running only what failed turns a twenty-minute deploy retry into a two-minute one, and the run history keeps both attempts so you can see what changed.
> [Docs →](https://docs.github.com/actions/managing-workflow-runs/re-running-workflows-and-jobs)
