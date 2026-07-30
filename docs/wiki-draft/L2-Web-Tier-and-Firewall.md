# L2 — Web Tier & Azure Firewall 🟡

**Goal:** add a real web tier to L1's network — 3 nginx VMs behind an **internal** load balancer — and put **Azure Firewall** in charge of all traffic in and out.

![L2 web tier and firewall traffic flow](diagram-l2.svg)

Files: [`labs/L2-web-tier/main.bicep`](../blob/main/labs/L2-web-tier/main.bicep) · [`labs/modules/subnet.bicep`](../blob/main/labs/modules/subnet.bicep)

> **Design note — why an internal LB?** A *public* LB in front of the VMs while a route table forces egress through the firewall causes asymmetric routing — return traffic takes a different path than inbound and connections silently die. The correct hub/spoke pattern used here: inbound through a firewall **DNAT rule** to an internal LB, egress through the firewall via the route table.

> ⚠️ **L1 must already be deployed with the same prefix** — L2 builds on that network.

<br>

# 🚀 Deploy L2 — pick any one of three ways

All three deploy the **same** template and give the **same** result.

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
> **Best if you like the command line.** Your values persist from L1 — nothing to re-type.

```powershell
$RG = "rg-lab-<yourname>"
az deployment group what-if --resource-group $RG --parameters labs/L2-web-tier/main.bicepparam
az deployment group create  --resource-group $RG --parameters labs/L2-web-tier/main.bicepparam
```

The Azure Firewall is the slow part (~10 min); the output includes your test URL (the firewall's public IP). *(New terminal / skipped L1? Run L1's one-time values block first.)*

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option 2 · GitHub Actions (push-button)

> [!TIP]
> **Best if you'd rather click a button.** Needs the one-time `Setup-Oidc.ps1` from L1.

On GitHub: **Actions → "Deploy L2 - Web Tier & Firewall" → Run workflow** (or `gh workflow run deploy-l2.yml`). Signs in with OIDC, runs Lint → What-if → Deploy.

<br>

---

## <img src="gh-copilot.png" width="30" align="top">&nbsp; Option 3 · GitHub Copilot (plain English)

> [!IMPORTANT]
> **Best if you'd rather describe the change** and have AI edit + deploy it.

Open **Copilot Chat → Agent mode**:

> Deploy `labs/L2-web-tier/main.bicep` to `rg-lab-<yourname>` with `az deployment group create`.

**Want to harden it first?** Ask:

> Limit the firewall's outbound rule to port 443 only (remove 80), run `az bicep build`, then deploy.

Copilot edits, verifies, and deploys — and fixes any error you paste back.

<br>

---

## ✅ Test it (3 ways)

```powershell
$RG = "rg-lab-<yourname>"; $PREFIX = $env:AZURE_PREFIX
```

1. **Round-robin through the firewall** — the page alternates `vm-$PREFIX-web0/1/2`:
   ```powershell
   $FW_IP = az network public-ip show -g $RG -n "pip-$PREFIX-fw" --query ipAddress -o tsv
   1..6 | ForEach-Object { curl -s "http://$FW_IP/" }
   ```
2. **Blocked vs allowed egress** — run on a web VM (source IP is the **firewall's** public IP):
   ```powershell
   az vm run-command invoke -g $RG -n "vm-$PREFIX-web0" `
     --command-id RunShellScript `
     --scripts "curl -s -m 5 https://ifconfig.me || echo HTTPS-BLOCKED; ping -c 2 -W 2 8.8.8.8 || echo ICMP-BLOCKED"
   ```
   HTTPS succeeds (allowed rule); ICMP is blocked (no rule).
3. **IP flow verify** —
   ```powershell
   az network watcher test-ip-flow -g $RG --vm "vm-$PREFIX-web0" `
     --direction Inbound --protocol TCP --local 10.1.1.5:80 --remote 10.0.1.4:40000
   ```

<br>

---

## ➡️ What carries forward

L3 keeps the hub and firewall, but replaces "VMs for apps" with containers and adds the data tier. → **[continue to L3](L3-Containers-and-Data)**. *(You may tear down only L2's firewall now if cost is a concern — L3 doesn't depend on it.)*
