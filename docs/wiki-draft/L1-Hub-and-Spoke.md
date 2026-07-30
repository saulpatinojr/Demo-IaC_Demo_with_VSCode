# L1 — Hub & Spoke Connectivity 🟢

**Goal:** deploy the network foundation every later lab builds on — a hub VNet and a peered spoke VNet, Azure Bastion for secure access, and one Linux test VM.

![L1 hub and spoke network topology](diagram-l1.svg)

Files: [labs/L1-hub-spoke/main.bicep](../blob/main/labs/L1-hub-spoke/main.bicep) and [labs/L1-hub-spoke/main.bicepparam](../blob/main/labs/L1-hub-spoke/main.bicepparam)

> **Why Bastion and not a VPN Gateway?** A gateway is the real-world hybrid entry point, but takes 30–45 minutes to deploy. Bastion gives the same "no public IP on the VM" story in ~10 minutes. The commented-out gateway module at the bottom of `main.bicep` shows the real thing.

---

## Deploy the Bicep template

The simplest path: deploy straight from the VS Code terminal with `az`. You only need to be signed in (`az login`, done in the [Start-Here Checklist](Start-Here-Checklist)) and inside your cloned repo folder.

### 1. One-time — save your lab values (persists across terminals)

Run this **once for the whole workshop**. It sets the values for this terminal *and* saves them so future terminals already have them — no re-pasting per lab:

```powershell
$vals = @{
  AZURE_PREFIX       = "<yourname>"                    # unique, max 12 chars, lowercase
  AZURE_LOCATION     = "eastus2"
  VM_ADMIN_PASSWORD  = "<Strong-Throwaway-Passw0rd!>"  # 12+ chars, 3 of 4 classes
  SQL_ADMIN_PASSWORD = "<Another-Throwaway-Passw0rd!>" # used by L3/L4; must not contain 'sqladminuser'
}
$vals.GetEnumerator() | ForEach-Object {
  Set-Item "env:$($_.Key)" $_.Value
  [Environment]::SetEnvironmentVariable($_.Key, $_.Value, 'User')
}
$RG = "rg-lab-<yourname>"   # your assigned resource group
```

> **Self-hosted only** (no resource group yet)? `az group create --name $RG --location $env:AZURE_LOCATION`

### 2. Preview, then deploy (two commands)

```powershell
az deployment group what-if --resource-group $RG --parameters labs/L1-hub-spoke/main.bicepparam
az deployment group create  --resource-group $RG --parameters labs/L1-hub-spoke/main.bicepparam
```

The `what-if` shows `+ Create` for everything (nothing exists yet). The `create` takes ~10 minutes (Bastion) and ends with `"provisioningState": "Succeeded"`.

> ### ⚙️ GitHub Actions — the hands-off alternative
> Rather deploy from CI with nothing on your laptop? Do the one-time OIDC setup (stores your creds in GitHub, see the [Deployment Guide](Deployment-Guide)):
> ```powershell
> ./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"
> ```
> Then GitHub → **Actions → "Deploy L1 - Hub & Spoke" → Run workflow** (or `gh workflow run deploy-l1.yml`). It logs in with OIDC and reads the stored secrets — Lint → What-if → Deploy, no local input.

---

## Test it (3 ways)

1. **Bastion SSH** — Portal → `vm-$env:AZURE_PREFIX-test` → **Connect → Bastion** → log in with `azureuser` + your VM password.
2. **Outbound works** — from that SSH session: `curl -s ifconfig.me` (works now; in L2 this same call is forced through the firewall).
3. **Peering is Connected** —
   ```powershell
   az network vnet peering list --resource-group $RG --vnet-name "vnet-$env:AZURE_PREFIX-spoke1" -o table
   ```
   `PeeringState` must be `Connected` in both directions.

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Prefer to **let Copilot drive** the edits and deploy? Open **Copilot Chat → Agent mode** and paste:
>
> > _Add a `snet-data` subnet `10.1.2.0/24` to the spoke VNet in `labs/L1-hub-spoke/main.bicep`, run `az bicep build` to verify, then deploy it with `az deployment group create --resource-group rg-lab-<yourname> --parameters labs/L1-hub-spoke/main.bicepparam`._
>
> **Why reach for Copilot here?**
> - **Change before you deploy** — it edits the Bicep, verifies with `az bicep build`, and runs the deploy for you.
> - **Explain anything** — _"why does the hub already reserve an `AzureFirewallSubnet` that nothing uses yet?"_
> - **Fix errors for you** — paste a red deploy error back into chat and it patches the template and retries.

---

## What carries forward

L2 deploys an Azure Firewall into the hub's reserved `AzureFirewallSubnet` and adds a `snet-web` subnet to this spoke. **Leave L1 deployed** → [continue to L2](L2-Web-Tier-and-Firewall).
