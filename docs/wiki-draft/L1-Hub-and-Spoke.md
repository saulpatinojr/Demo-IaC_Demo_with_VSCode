# L1 — Hub & Spoke Connectivity 🟢

**Goal:** deploy the network foundation every later lab builds on — a hub VNet and a peered spoke VNet, Azure Bastion for secure access, and one Linux test VM.

![L1 hub and spoke network topology](diagram-l1.svg)

Files: [labs/L1-hub-spoke/main.bicep](../blob/main/labs/L1-hub-spoke/main.bicep) · [labs/L1-hub-spoke/main.bicepparam](../blob/main/labs/L1-hub-spoke/main.bicepparam)

> **Why Bastion and not a VPN Gateway?** A gateway is the real-world hybrid entry point, but takes 30–45 minutes. Bastion gives the same "no public IP on the VM" story in ~10 minutes. The commented-out gateway module at the bottom of `main.bicep` shows the real thing.

<br>

# 🚀 Deploy L1 — pick any one of three ways

All three deploy the **same** template and give the **same** result. Choose the one you're most comfortable with.

<table>
<tr>
<td align="center" width="240"><img src="bicep.png" width="70"><br><br><b>1 · Bicep CLI</b><br><sub>Copy-paste in the terminal</sub></td>
<td align="center" width="240"><img src="gh-actions.png" width="70"><br><br><b>2 · GitHub Actions</b><br><sub>One button in the browser</sub></td>
<td align="center" width="240"><img src="gh-copilot.png" width="70"><br><br><b>3 · GitHub Copilot</b><br><sub>Ask AI in plain English</sub></td>
</tr>
</table>

<br>

---

## <img src="bicep.png" width="30" align="top">&nbsp; Option 1 · Bicep from the terminal

> [!NOTE]
> **Best if you like the command line** and want to watch each step happen.

**Do this once** — fill in a small file instead of typing variables:

1. Copy **`lab-settings.csv.example`** to **`lab-settings.csv`** (repo root) and fill in your values — open it in Excel or VS Code, it's just one row.
2. Load them (add `-Persist` to keep them in future terminals too):
   ```powershell
   ./scripts/Load-LabSettings.ps1 -Persist
   ```

**Then deploy** (preview first, then create):

```powershell
az deployment group what-if --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L1-hub-spoke/main.bicepparam
az deployment group create  --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L1-hub-spoke/main.bicepparam
```

Takes ~10 minutes (Bastion is the slow part) and ends with `"provisioningState": "Succeeded"`.

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option 2 · GitHub Actions (push-button)

> [!TIP]
> **Best if you'd rather click a button** and let the cloud do the work — nothing installed locally.
> No `lab-settings.csv` needed here — Actions uses the GitHub secrets from `Setup-Oidc.ps1`.

**Do this once** — store your credentials in GitHub with the setup script:

```powershell
./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"
```

**Then deploy:** on GitHub go to **Actions → "Deploy L1 - Hub & Spoke" → Run workflow**.

That's it. It signs in with OIDC (no password anywhere) and runs **Lint → What-if → Deploy** for you. Prefer the terminal? `gh workflow run deploy-l1.yml`.

<br>

---

## <img src="gh-copilot.png" width="30" align="top">&nbsp; Option 3 · GitHub Copilot (plain English)

> [!IMPORTANT]
> **Best if you'd rather describe what you want** — and have AI change the template and deploy it for you.

Copilot runs the deploy **locally**, so load your values once first (same file as Option 1): `./scripts/Load-LabSettings.ps1`.

Open **Copilot Chat → Agent mode** and paste:

> Deploy `labs/L1-hub-spoke/main.bicep` to my lab resource group (`$env:AZURE_RESOURCE_GROUP`) with `az deployment group create`.

**Want to change something first?** Just ask — for example:

> Add a `snet-data` subnet `10.1.2.0/24` to the spoke VNet, run `az bicep build` to check it, then deploy.

Copilot edits the Bicep, verifies it compiles, and runs the deploy. If a command errors, paste the message back and it fixes it.

<br>

---

## ✅ Test it (3 ways)

1. **Bastion SSH** — Portal → `vm-$env:AZURE_PREFIX-test` → **Connect → Bastion** → log in with `azureuser` + your VM password.
2. **There is no way out yet** — from that SSH session:
   ```bash
   curl -s -m 5 ifconfig.me || echo "NO EGRESS - as designed"
   ```
   This **times out, and that is the correct result.** The VM has no public IP, no NAT gateway and no route to a firewall, and [default outbound access was retired on 30 September 2025](https://azure.microsoft.com/en-us/updates?id=default-outbound-access-for-vms-in-azure-will-be-retired-transition-to-a-new-method-of-internet-access) — so a VM in a new VNet gets no internet unless you give it one explicitly. L2 is what gives it one, through the firewall. Run the same command again at the end of L2.
3. **Peering is Connected** —
   ```powershell
   az network vnet peering list --resource-group $env:AZURE_RESOURCE_GROUP --vnet-name "vnet-$env:AZURE_PREFIX-spoke1" -o table
   ```
   `PeeringState` must be `Connected` in both directions.

<br>

---

## ➡️ What carries forward

L2 deploys an Azure Firewall into the hub's reserved `AzureFirewallSubnet`, adds a `snet-web` subnet to this spoke, and routes **this** subnet's traffic through the firewall too — which is what finally gives the test VM its internet access. **Leave L1 deployed** → **[continue to L2](L2-Web-Tier-and-Firewall)**.
