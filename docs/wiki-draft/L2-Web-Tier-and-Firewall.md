# L2 — Web Tier & Azure Firewall 🟡

**Goal:** add a real web tier to L1's network — 3 nginx VMs behind an **internal** load balancer — and put **Azure Firewall** in charge of all traffic in and out.

![L2 web tier and firewall traffic flow](diagram-l2.svg)

Files: [`labs/L2-web-tier/main.bicep`](../blob/main/labs/L2-web-tier/main.bicep), [`labs/modules/subnet.bicep`](../blob/main/labs/modules/subnet.bicep)

> **Design note — why an internal LB?** If you put a *public* LB in front of the VMs while a route table forces their egress through the firewall, return traffic takes a different path than inbound (asymmetric routing) and connections silently die. The correct hub/spoke pattern — used here — is: inbound through a firewall **DNAT rule** to an internal LB, egress through the firewall via the route table.

---

## Deploy the Bicep template

**L1 must already be deployed with the same prefix** — L2 adds to that network. Your creds are already stored from the one-time `Setup-Oidc.ps1` run, so there's **nothing to paste**.

### 1. (Optional) confirm setup

```powershell
gh secret list
```

Missing anything? Re-run the one-shot: `./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"`

### 2. Run the deploy

GitHub → **Actions → "Deploy L2 - Web Tier & Firewall" → Run workflow** (or `gh workflow run deploy-l2.yml`). Same three stages — Lint → What-if → Deploy. The Azure Firewall is the slow part (~10 min); the run output includes your test URL (the firewall's public IP).

---

## Test it (3 ways)

```powershell
$RG = "rg-lab-<yourname>"; $PREFIX = "<yourname>"
```

1. **Round-robin through the firewall** — the page alternates hostnames `vm-$PREFIX-web0/1/2`:
   ```powershell
   $FW_IP = az network public-ip show -g $RG -n "pip-$PREFIX-fw" --query ipAddress -o tsv
   1..6 | ForEach-Object { curl -s "http://$FW_IP/" }
   ```
2. **Blocked vs allowed egress** — run on a web VM (note the source IP is the **firewall's** public IP):
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

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Prefer to **let Copilot drive** the edits and deploy? Open **Copilot Chat → Agent mode**:
>
> > _Limit the firewall's outbound network rule in `labs/L2-web-tier/main.bicep` to port 443 only (remove 80), run `az bicep build`, then commit, push, and trigger `gh workflow run deploy-l2.yml`._
>
> **Why reach for Copilot here?**
> - **Tighten security before deploy** — the prompt above hardens egress, verifies, and redeploys in one go.
> - **Scale the tier** — _"add a 4th web VM by changing `vmCount` and confirm the outputs update"_.
> - **Explain the tricky bit** — _"why would a public load balancer break this design?"_
>
> No creds to handle — the workflow logs in with OIDC using your stored secrets.

---

## What carries forward

L3 keeps the hub and firewall, but replaces "VMs for apps" with containers and adds the data tier. → [continue to L3](L3-Containers-and-Data). (You may tear down **only** L2's firewall at this point if cost is a concern — L3 doesn't depend on it.)
