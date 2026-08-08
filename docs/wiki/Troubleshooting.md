# Troubleshooting

> [!TIP]
> **Fastest fix for OIDC and secret issues:** re-run `./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-techdemo-<yourname>" -Prefix "<yourname>"` — it is idempotent and repairs a missing credential, role assignment, or secret in one shot. The preflight step in each workflow also tells you *exactly which secret* is missing before login is even attempted.

---

## 🔐 OIDC and login failures

| Symptom | Cause and fix |
|---------|--------------|
| `ResourceGroup is required (also under -WhatIf)` from `Setup-Oidc.ps1` | You ran it without `-ResourceGroup`. It is required on **every** run, self-hosted included — the workflows always deploy into a named group. Pass the group your instructor assigned, or create your own first: `az group create --name "rg-techdemo-<yourname>" --location eastus2`. |
| `Resource group '<name>' does not exist in subscription` | **No lab creates the group** — it must exist before setup. Check what you actually have with `az group list --query "[].name" -o tsv`, and make sure you didn't type the `<yourname>` placeholder literally. |
| `Missing repo secret 'AZURE_RESOURCE_GROUP'` (workflow fails immediately) | The preflight check caught a missing secret. Re-run `Setup-Oidc.ps1 -ResourceGroup ...` or set it manually: `gh secret set AZURE_RESOURCE_GROUP --body "rg-techdemo-<yourname>"`. |
| `Missing repo secret 'VM_ADMIN_PASSWORD'` or `SQL_ADMIN_PASSWORD'` | Same as above — re-run the setup script to regenerate passwords. |
| `AADSTS700213: No matching federated identity record` | The federated credential `subject` does not match. It must be exactly `repo:<user>/Demo-IaC_Demo_with_VSCode:ref:refs/heads/main` — check fork owner, repo name, and branch name. Re-run `Setup-Oidc.ps1` to recreate it. |
| `AADSTS70021` / audience errors | The `audiences` field must be `api://AzureADTokenExchange`. Re-run the setup script. |
| `AuthorizationFailed` during deploy | The service principal needs **Contributor on the resource group**. Re-run `Setup-Oidc.ps1 -ResourceGroup "rg-techdemo-<yourname>"`. |
| Login step fails with "id-token: write" hint | The workflow's `permissions:` block is missing or was removed. Do not remove it when editing workflows with Copilot. |

---

## 🧭 `gh` command issues (multiple remotes / wrong repo)

| Symptom | Cause and fix |
|---------|--------------|
| `gh secret list` returns `! Multiple remotes detected. Requiring disambiguation.` | Your repo has both `origin` (your fork) and `upstream` (instructor) remotes. `gh` doesn't know which one to use. Fix: run `gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode` once inside the repo folder. |
| `gh secret list` returns `no secrets found` after disambiguation | You selected the instructor's repo (`saulpatinojr/…`) instead of your own fork. Fix: run `gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode`. |
| `gh secret list` returns `no secrets found` (correct repo, correct fork) | `Setup-Oidc.ps1` has not been run yet for this fork. Go to Section G of [Start Here Checklist — Part 2](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist-Part-2) and run the script. |
| Any `gh` command targets the wrong repo | Run `gh repo set-default <your-username>/Demo-IaC_Demo_with_VSCode` from inside the cloned folder. To verify: `gh repo view --json nameWithOwner -q .nameWithOwner`. |

---

## 🧱 Bicep and AVM

| Symptom | Cause and fix |
|---------|--------------|
| `BCP192: unable to restore br/public:avm/...` | No network path to `mcr.microsoft.com` (proxy or firewall). Run `az bicep restore --file <file>` to see details. |
| `BCP037: property not allowed` after editing | AVM module parameters differ between versions. Keep the pinned version from the ref and check the module docs: `https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/...` |
| What-if shows unexpected deletions | You renamed a resource — ARM sees a delete + create. Names are identity; rename carefully. |
| `ResourceGroupNotFound` | `AZURE_RESOURCE_GROUP` secret is wrong or the resource group was not pre-created. Check: `az group show --name <name>`. |

---

## 🧪 Lab-specific issues

| Symptom | Cause and fix |
|---------|--------------|
| **L1**: VM deploy fails on password | Must be 12+ characters with 3 of 4 character classes (uppercase, lowercase, digit, symbol) and must not contain the username. Re-run `Setup-Oidc.ps1` to regenerate. |
| **L2**: `curl http://<fw-ip>` times out | Firewall provisioning takes ~10 minutes *after* the workflow reports success. Also confirm the DNAT rule exists: `az network firewall nat-rule collection list -g <rg> -f afw-<prefix>-hub`. |
| **L2**: Web VMs unhealthy in the load balancer | `cloud-init` needs outbound HTTP (port 80) to install nginx. If the egress rule was tightened to HTTPS-only *before* first deploy, `apt-get` failed silently. Redeploy or loosen the rule first. |
| **L2**: Everything broke after adding a public LB | Asymmetric routing — inbound via public LB, return path via firewall. Use the DNAT + internal LB pattern already in the template. See the design note in the [L2 guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/L2-Web-Tier-and-Firewall). |
| **L3**: Connecting to SQL from your laptop fails | That is correct and expected — public access is disabled. SQL is only reachable from inside the VNet via private endpoint. |
| **L3**: Container cannot reach SQL by name | The private DNS zone is linked to spoke2 only. To link another VNet: `az network private-dns link vnet create -g <rg> -z "privatelink.database.windows.net" -n <link-name> -v <vnet-id> -e false`. |
| **L3**: SQL or Key Vault name already taken | These names are globally unique. The template appends a `uniqueString` suffix per subscription+prefix — collisions mean someone else used the same prefix. Change `-Prefix`. |
| **L4**: Front Door returns 502 or 404 at first | Origin propagation takes up to ~10 minutes after creation. Check origin health: Portal → Front Door → Origin groups → health status. |
| **L4**: Failover group creation fails | `SQL_ADMIN_PASSWORD` must match L3's exactly, and L3 must be fully deployed (database `sqldb-<prefix>-app` must exist on the primary server). |
| Quota / SKU not available in region | `az vm list-skus -l eastus2 --size Standard_B2s -o table`. If unavailable, pick a different region and use it consistently for ALL labs via the `-Location` flag in `Setup-Oidc.ps1`. |

---

## ⚙️ Lab settings and environment variables

| Symptom | Cause and fix |
|---------|--------------|
| Terminal commands fail with `$env:AZURE_RESOURCE_GROUP` empty | Run `./scripts/Load-LabSettings.ps1` (or `Load-LabSettings.ps1 -Persist` once to save permanently). |
| `lab-settings.csv not found` | Copy the example file: `Copy-Item lab-settings.csv.example lab-settings.csv`, then fill in your values. |

---

## 🤖 Copilot agent mode

- **Agent made a change that does not compile** → tell it: *"Run `az bicep build` on the file and fix the errors."* It iterates.
- **Agent cannot run `az`** → make sure Azure CLI is installed and you are logged in within the same terminal profile that VS Code uses.
- **Suggestions use old API versions or non-AVM resources** → say: *"Use the pinned AVM module versions already used in this repo."*
- **Agent edited the wrong file** → undo with `Ctrl+Z` or Source Control → discard changes, then re-prompt with the specific file path.

---

## 🔍 Getting deployment details from the CLI

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
> **You just used it:** when a deploy fails, you do not have to start over. A transient Azure error, or a secret you have just corrected, only needs the failed part to run again.
> **Find it:** open the failed run in the **Actions** tab → **Re-run jobs** → *Re-run failed jobs*. Use **Download log archive** on the same menu to grab the full output for a bug report.
> **Beyond the lab:** re-running only what failed turns a twenty-minute deploy retry into a two-minute one, and the run history keeps both attempts so you can see what changed.
> [Docs →](https://docs.github.com/actions/managing-workflow-runs/re-running-workflows-and-jobs)
