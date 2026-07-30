# L1 — Hub & Spoke Connectivity 🟢

**Goal:** deploy the network foundation every later lab builds on — a hub VNet and a peered spoke VNet, Azure Bastion for secure access, and one Linux test VM.

![L1 hub and spoke network topology](diagram-l1.svg)

Files: [labs/L1-hub-spoke/main.bicep](../blob/main/labs/L1-hub-spoke/main.bicep) and [labs/L1-hub-spoke/main.bicepparam](../blob/main/labs/L1-hub-spoke/main.bicepparam)

> **Why Bastion and not a VPN Gateway?** A gateway is the real-world hybrid entry point, but takes 30–45 minutes to deploy. Bastion gives the same "no public IP on the VM" story in ~10 minutes. The commented-out gateway module at the bottom of `main.bicep` shows the real thing.

---

## Deploy the Bicep template

Your credentials were saved **once** by the `Setup-Oidc.ps1` one-shot (see the [Deployment Guide](Deployment-Guide)). GitHub Actions signs in to Azure with **OIDC** and reads them — so there is **nothing to paste for each lab**.

### 1. Confirm your one-time setup (only needed once for the whole workshop)

```powershell
gh secret list
gh variable list
```

You should see `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `VM_ADMIN_PASSWORD`, plus the `AZURE_PREFIX` and `AZURE_LOCATION` variables. Missing any? Run the one-shot (it stores everything for you):

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"
```

### 2. Run the deploy

GitHub → **Actions → "Deploy L1 - Hub & Spoke" → Run workflow**. It runs three stages and needs **no input from you**:

1. **Lint** — `az bicep build` (compile + linter)
2. **What-if** — previews `+ Create / ~ Modify / - Delete` per resource
3. **Deploy** — `az deployment group create` into your resource group

Takes ~10 minutes (Bastion is the slow part). The run log ends with `Succeeded`.

> Want to trigger it from the terminal instead of clicking? `gh workflow run deploy-l1.yml` (then watch with `gh run watch`).

---

## Test it (3 ways)

Set two non-secret values for the commands below (your RG and prefix):

```powershell
$RG = "rg-lab-<yourname>"; $PREFIX = "<yourname>"
```

1. **Bastion SSH** — Portal → `vm-$PREFIX-test` → **Connect → Bastion** → log in with `azureuser` + your password.
2. **Outbound works** — from that SSH session: `curl -s ifconfig.me` (works now; in L2 this same call is forced through the firewall).
3. **Peering is Connected** —
   ```powershell
   az network vnet peering list --resource-group $RG --vnet-name "vnet-$PREFIX-spoke1" -o table
   ```
   `PeeringState` must be `Connected` in both directions.

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> The steps above are the plain Bicep + Actions path. If you'd rather **let Copilot drive**, open **Copilot Chat → Agent mode** and paste:
>
> > _Add a `snet-data` subnet `10.1.2.0/24` to the spoke VNet in `labs/L1-hub-spoke/main.bicep`, run `az bicep build` to verify, then commit, push, and trigger the deploy with `gh workflow run deploy-l1.yml`._
>
> **Why reach for Copilot here?**
> - **Change before you deploy** — it edits the Bicep, verifies with `az bicep build`, pushes, and kicks off the workflow for you.
> - **Explain anything** — _"why does the hub already reserve an `AzureFirewallSubnet` that nothing uses yet?"_
> - **Fix errors for you** — paste a failed run's error back into chat and it patches the template and reruns.
>
> No creds to handle — the workflow still logs in with OIDC using the secrets from your one-time setup.

---

## What carries forward

L2 deploys an Azure Firewall into the hub's reserved `AzureFirewallSubnet` and adds a `snet-web` subnet to this spoke. **Leave L1 deployed** → [continue to L2](L2-Web-Tier-and-Firewall).
