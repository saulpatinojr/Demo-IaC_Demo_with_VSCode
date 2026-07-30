# L1 — Hub & Spoke Connectivity 🟢

**Goal:** deploy the network foundation every later lab builds on — a hub VNet and a peered spoke VNet, Azure Bastion for secure access, and one Linux test VM.

![L1 hub and spoke network topology](diagram-l1.svg)

Files: [labs/L1-hub-spoke/main.bicep](../blob/main/labs/L1-hub-spoke/main.bicep) and [labs/L1-hub-spoke/main.bicepparam](../blob/main/labs/L1-hub-spoke/main.bicepparam)

> **Why Bastion and not a VPN Gateway?** A gateway is the real-world hybrid entry point, but takes 30–45 minutes to deploy. Bastion gives the same "no public IP on the VM" story in ~10 minutes. The commented-out gateway module at the bottom of `main.bicep` shows the real thing.

---

## Deploy the Bicep template

This is the main path. Three commands from the VS Code terminal — **lint → preview → deploy**. You only need to be signed in to Azure (`az login`, done in the [Start-Here Checklist](Start-Here-Checklist)) and inside your cloned repo folder.

### 1. Set your values (once per terminal)

Copy/paste this block, changing only the three values at the top:

```powershell
$RG                    = "rg-lab-<yourname>"          # your assigned resource group
$env:AZURE_PREFIX      = "<yourname>"                 # unique, max 12 chars, lowercase
$env:AZURE_LOCATION    = "eastus2"
$env:VM_ADMIN_PASSWORD = "<Strong-Throwaway-Passw0rd!>"   # 12+ chars, 3 of 4: upper/lower/digit/symbol
```

> **Self-hosted only** (no resource group yet)? Create one first:
> ```powershell
> az group create --name $RG --location $env:AZURE_LOCATION
> ```

### 2. Preview what will be created (safe — changes nothing)

```powershell
az deployment group what-if `
  --resource-group $RG `
  --parameters labs/L1-hub-spoke/main.bicepparam
```

Read the `+ Create` lines — this is IaC's safety net. Nothing exists yet, so everything shows as **Create**.

### 3. Deploy

```powershell
az deployment group create `
  --resource-group $RG `
  --parameters labs/L1-hub-spoke/main.bicepparam
```

Takes ~10 minutes (Bastion is the slow part). When it finishes you'll see `"provisioningState": "Succeeded"`.

> Prefer CI/CD over your laptop? The repo also ships a **GitHub Actions** workflow that runs these same three stages with passwordless OIDC — see the [Deployment Guide](Deployment-Guide). The local commands above are the simplest way to see a deploy end to end.

---

## Test it (3 ways)

1. **Bastion SSH** — Portal → `vm-<prefix>-test` → **Connect → Bastion** → log in with `azureuser` + your password.
2. **Outbound works** — from that SSH session: `curl -s ifconfig.me` (works now; in L2 this same call is forced through the firewall).
3. **Peering is Connected** —
   ```powershell
   az network vnet peering list `
     --resource-group $RG `
     --vnet-name "vnet-$env:AZURE_PREFIX-spoke1" `
     -o table
   ```
   `PeeringState` must be `Connected` in both directions.

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Everything above is the plain Bicep path. If you'd rather **let Copilot drive**, open **Copilot Chat → Agent mode** and paste a prompt like:
>
> > _Deploy `labs/L1-hub-spoke/main.bicep` to my resource group `rg-lab-<yourname>` with `az deployment group create`. Use prefix `<yourname>`, location `eastus2`, and prompt me for the VM admin password._
>
> **Why reach for Copilot here?**
> - **Change before you deploy** — _"add a `snet-data` subnet `10.1.2.0/24` to the spoke VNet, then redeploy"_ — Copilot edits the Bicep, runs `az bicep build`, and reruns the command.
> - **Explain anything** — _"why does the hub already reserve an `AzureFirewallSubnet` that nothing uses yet?"_
> - **Fix errors for you** — paste a red deploy error back into chat and it patches the template and retries.
>
> Same result, less typing — and you learn the "why" as you go.

---

## What carries forward

L2 deploys an Azure Firewall into the hub's reserved `AzureFirewallSubnet` and adds a `snet-web` subnet to this spoke. **Leave L1 deployed** → [continue to L2](L2-Web-Tier-and-Firewall).
