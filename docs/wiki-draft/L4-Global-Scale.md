# L4 — Global Scale 🔴

**Goal:** the "production upgrade" of L3 — survive a regional outage. A second-region app stack, an **Azure SQL failover group**, and **Azure Front Door** as the single global entry point with health-probed failover.

![L4 global scale with Front Door and SQL failover](diagram-l4.svg)

Files: [`labs/L4-global/main.bicep`](../blob/main/labs/L4-global/main.bicep), [`labs/modules/sql-failover-group.bicep`](../blob/main/labs/modules/sql-failover-group.bicep)

---

## Deploy the Bicep template

**L3 must already be deployed, and the SQL password must match L3's.** Same three commands.

### 1. Set your values (once per terminal)

```powershell
$RG                     = "rg-lab-<yourname>"
$env:AZURE_PREFIX       = "<yourname>"
$env:SQL_ADMIN_PASSWORD = "<same password you used for L3>"
```

### 2. Preview

```powershell
az deployment group what-if `
  --resource-group $RG `
  --parameters labs/L4-global/main.bicepparam
```

### 3. Deploy

```powershell
az deployment group create `
  --resource-group $RG `
  --parameters labs/L4-global/main.bicepparam
```

The deployment output prints your Front Door endpoint (`<name>.azurefd.net`). Front Door propagation can take ~10 minutes after the first deploy.

> Prefer CI/CD? Same three stages run in the **GitHub Actions** workflow — see the [Deployment Guide](Deployment-Guide).

---

## Test it (3 ways)

1. **Global entry point** —
   ```powershell
   $FDE = "<your-fde-endpoint>.azurefd.net"
   curl -sI "https://$FDE/"
   ```
   You should see an HTTP success response from the primary region.
2. **Simulated regional failure** — stop the primary app and watch Front Door reroute to the secondary region (probes take 30–90 s):
   ```powershell
   $APP = "ca-$env:AZURE_PREFIX-web"
   $REVISION = az containerapp revision list -g $RG -n $APP --query "[0].name" -o tsv
   az containerapp revision deactivate -g $RG -n $APP --revision $REVISION
   curl -s "https://$FDE/"
   ```
   The endpoint still responds, now through the secondary region. Reactivate the revision afterwards.
3. **Database failover** —
   ```powershell
   $PRIMARY_SQL = az sql server list -g $RG --query "[?starts_with(name, 'sql-$env:AZURE_PREFIX-') && !ends_with(name, '-dr')].name | [0]" -o tsv
   $DR_SQL      = az sql server list -g $RG --query "[?starts_with(name, 'sql-$env:AZURE_PREFIX-') &&  ends_with(name, '-dr')].name | [0]" -o tsv
   $FOG         = az sql failover-group list -g $RG --server $PRIMARY_SQL --query "[0].name" -o tsv
   az sql failover-group set-primary -g $RG --server $DR_SQL --name $FOG
   ```
   The secondary is now primary; fail back the same way in reverse.

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Prefer to **let Copilot drive**? Open **Copilot Chat → Agent mode**:
>
> > _Deploy `labs/L4-global/main.bicep` to resource group `rg-lab-<yourname>` with `az deployment group create` using prefix `<yourname>`, and prompt me for the SQL admin password._
>
> **Why reach for Copilot here?**
> - **Change the routing strategy** — _"switch the Front Door origin group to weighted round-robin between both regions instead of priority failover, then redeploy"_.
> - **Explain the failover story** — _"what does the SQL failover-group listener endpoint give the application during a region outage?"_
> - **Fix errors for you** — paste any deploy error and Copilot patches the template and retries.
>
> Same Bicep, Copilot handles the editing and re-running.

---

## You're done 🎉

Tear everything down when finished — Front Door, Firewall, Bastion and SQL all bill while idle:

```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup $RG -WhatIf
./scripts/Cleanup-Labs.ps1 -ResourceGroup $RG
```

Then check [Troubleshooting](Troubleshooting) and [Tools and References](Tools-and-References) for going further.
