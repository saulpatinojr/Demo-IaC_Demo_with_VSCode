# L4 — Global Scale 🔴

**Goal:** the "production upgrade" of L3 — survive a regional outage. A second-region app stack, an **Azure SQL failover group**, and **Azure Front Door** as the single global entry point with health-probed failover.

![L4 global scale with Front Door and SQL failover](diagram-l4.svg)

Files: [`labs/L4-global/main.bicep`](../blob/main/labs/L4-global/main.bicep), [`labs/modules/sql-failover-group.bicep`](../blob/main/labs/modules/sql-failover-group.bicep)

---

## Deploy the Bicep template

**L3 must already be deployed**, and L4 reuses the **same** stored `SQL_ADMIN_PASSWORD` — so the failover group's two servers match. Nothing to paste.

### 1. (Optional) confirm setup

```powershell
gh secret list      # expect SQL_ADMIN_PASSWORD
gh variable list    # expect AZURE_PREFIX
```

### 2. Run the deploy

GitHub → **Actions → "Deploy L4 - Global Scale" → Run workflow** (or `gh workflow run deploy-l4.yml`). Lint → What-if → Deploy. The run output prints your Front Door endpoint (`<name>.azurefd.net`). Front Door propagation can take ~10 minutes after the first deploy.

---

## Test it (3 ways)

```powershell
$RG = "rg-lab-<yourname>"; $PREFIX = "<yourname>"; $FDE = "<your-fde-endpoint>.azurefd.net"
```

1. **Global entry point** —
   ```powershell
   curl -sI "https://$FDE/"
   ```
   You should see an HTTP success response from the primary region.
2. **Simulated regional failure** — stop the primary app and watch Front Door reroute to the secondary region (probes take 30–90 s):
   ```powershell
   $APP = "ca-$PREFIX-web"
   $REVISION = az containerapp revision list -g $RG -n $APP --query "[0].name" -o tsv
   az containerapp revision deactivate -g $RG -n $APP --revision $REVISION
   curl -s "https://$FDE/"
   ```
   The endpoint still responds, now through the secondary region. Reactivate the revision afterwards.
3. **Database failover** —
   ```powershell
   $PRIMARY_SQL = az sql server list -g $RG --query "[?starts_with(name, 'sql-$PREFIX-') && !ends_with(name, '-dr')].name | [0]" -o tsv
   $DR_SQL      = az sql server list -g $RG --query "[?starts_with(name, 'sql-$PREFIX-') &&  ends_with(name, '-dr')].name | [0]" -o tsv
   $FOG         = az sql failover-group list -g $RG --server $PRIMARY_SQL --query "[0].name" -o tsv
   az sql failover-group set-primary -g $RG --server $DR_SQL --name $FOG
   ```
   The secondary is now primary; fail back the same way in reverse.

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Prefer to **let Copilot drive**? Open **Copilot Chat → Agent mode**:
>
> > _Switch the Front Door origin group in `labs/L4-global/main.bicep` to weighted round-robin between both regions instead of priority failover, run `az bicep build`, then commit, push, and trigger `gh workflow run deploy-l4.yml`._
>
> **Why reach for Copilot here?**
> - **Change the routing strategy** — the prompt above edits, verifies, and redeploys in one go.
> - **Explain the failover story** — _"what does the SQL failover-group listener endpoint give the application during a region outage?"_
> - **Fix errors for you** — paste any failed run's error and Copilot patches the template and reruns.
>
> No creds to handle — the workflow logs in with OIDC using your stored secrets.

---

## You're done 🎉

Tear everything down when finished — Front Door, Firewall, Bastion and SQL all bill while idle:

```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-<yourname>" -WhatIf
./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-<yourname>"
```

Then check [Troubleshooting](Troubleshooting) and [Tools and References](Tools-and-References) for going further.
