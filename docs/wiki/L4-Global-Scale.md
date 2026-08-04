# L4 — Global Scale 🔴

**Goal:** the "production upgrade" of L3 — survive a regional outage. A second-region app stack, an **Azure SQL failover group**, and **Azure Front Door** as the single global entry point with health-probed failover.

```mermaid
flowchart LR
  USERS(["Users worldwide"])
  AFD["afd-iacdemo-xxxxxx<br/>Front Door Standard<br/>health probe GET / every 30s"]

  subgraph P["PRIMARY · eastus2 · all of L3"]
    APP1["ca-iacdemo-web<br/>priority 1"]
    SQL1["sql-iacdemo-xxxxxx<br/>private endpoint + private DNS"]
  end

  subgraph S["SECONDARY · westus2 · deliberately slim"]
    APP2["ca-iacdemo-web2<br/>cae-iacdemo-l4<br/>priority 2<br/>no VNet, no Key Vault, no App Insights"]
    SQL2["sql-iacdemo-xxxxxx-dr<br/>public access DISABLED<br/>NO private endpoint"]
  end

  FOG["fog-iacdemo-xxxxxx<br/>SQL failover group<br/>listener survives failover"]

  USERS --> AFD
  AFD -->|"priority 1, while healthy"| APP1
  AFD -. "priority 2, only if probes fail" .-> APP2
  APP1 --> SQL1
  SQL1 <-->|"geo-replication"| SQL2
  FOG --- SQL1
  FOG --- SQL2
  APP2 -. "NO DATA PATH<br/>no VNet, no private endpoint,<br/>public access disabled" .-> SQL2

  classDef compute fill:#eefaf0,stroke:#3a9d5d,color:#1a1a1a
  classDef data fill:#f5eefc,stroke:#7c4dbe,color:#1a1a1a
  classDef net fill:#eef4ff,stroke:#4472c4,color:#1a1a1a
  classDef blocked fill:#fdecea,stroke:#c0392b,color:#1a1a1a
  class APP1,APP2 compute
  class SQL1,FOG data
  class AFD net
  class SQL2 blocked
```

<details><summary>Text description of this diagram</summary>

Front Door is the single global entry point. It health-probes both regions with
`GET /` every 30 seconds and sends traffic to the **priority 1** origin — the
L3 app in `eastus2` — falling back to the **priority 2** secondary in
`westus2` only when the primary stops answering.

The two SQL servers are joined by a **failover group**. Its listener hostname
is the one endpoint that survives a failover: point an application at
`fog-...database.windows.net` and it follows whichever server is currently
primary, without a connection-string change.

The dashed red line is deliberate and worth studying. The secondary region is
**slim**: no VNet integration, no Key Vault, no Application Insights. And
`sql-iacdemo-xxxxxx-dr` has public access disabled with **no private endpoint**
— so after a failover, nothing can actually reach the promoted database. The
ARM operation succeeds and the data path does not exist.

That is a Well-Architected gap you can close yourself, and the Copilot prompt
further down this page does exactly that.

</details>

Files: [`labs/L4-global/main.bicep`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/labs/L4-global/main.bicep) · [`labs/modules/sql-failover-group.bicep`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/labs/modules/sql-failover-group.bicep)

> ⚠️ **L3 must already be deployed** — L4 reuses the **same** SQL password so the failover group's two servers match.

<br>

## 🚀 Deploy L4 — pick any one of three ways

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
> **Best if you like the command line.** Values are already loaded from `lab-settings.csv` (set up in L1) — nothing to re-type.

```powershell
az deployment group what-if --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L4-global/main.bicepparam
az deployment group create  --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L4-global/main.bicepparam
```

The output prints your Front Door endpoint (`<name>.azurefd.net`). Front Door propagation can take ~10 minutes after the first deploy.

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option 2 · GitHub Actions (push-button)

> [!TIP]
> **Best if you'd rather click a button.** Needs the one-time `Setup-Oidc.ps1` from L1.
> No `lab-settings.csv` needed — Actions uses the GitHub secrets from that setup.

On GitHub: **Actions → "Deploy L4 - Global Scale" → Run workflow** (or `gh workflow run deploy-l4.yml`). Signs in with OIDC, runs Lint → What-if → Deploy.

<br>

---

## <img src="gh-copilot.png" width="30" align="top">&nbsp; Option 3 · GitHub Copilot (plain English)

> [!IMPORTANT]
> **Best if you'd rather describe the change** and have AI edit + deploy it.

Copilot runs the deploy **locally**, so load your values once first (same file as Option 1): `./scripts/Load-LabSettings.ps1`.

Open **Copilot Chat → Agent mode**:

> Deploy `labs/L4-global/main.bicep` to my lab resource group (`$env:AZURE_RESOURCE_GROUP`) with `az deployment group create`.

**Want to change the routing first?** Ask:

> Switch the Front Door origin group in `labs/L4-global/main.bicep` to weighted round-robin between both regions instead of priority failover, run `az bicep build`, then deploy.

**Or close the Well-Architected gap** — the flagship exercise for this lab:

> In `labs/L4-global/main.bicep`, the DR server `sql-<prefix>-<suffix>-dr` sets `publicNetworkAccess: 'Disabled'` but has no private endpoint, so nothing can reach it after a failover. Add a secondary VNet in `westus2` with a private-endpoint subnet, a private DNS zone linked to it, and a private endpoint on the DR server. Run `az bicep build`, then `what-if`.

Copilot edits, verifies, and deploys — and fixes any error you paste back.

<br>

---

## ✅ Test it (3 ways)

```powershell
$RG = $env:AZURE_RESOURCE_GROUP; $PREFIX = $env:AZURE_PREFIX; $FDE = "<your-fde-endpoint>.azurefd.net"
```

1. **Global entry point** —
   ```powershell
   curl.exe -sI "https://$FDE/"
   ```
   You should see an HTTP success response from the primary region.
2. **Simulated regional failure** — stop the primary app and watch Front Door reroute to the secondary region (probes take 30–90 s):
   ```powershell
   $APP = "ca-$PREFIX-web"
   $REVISION = az containerapp revision list -g $RG -n $APP --query "[0].name" -o tsv
   az containerapp revision deactivate -g $RG -n $APP --revision $REVISION
   curl.exe -s "https://$FDE/"
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

<br>

---

## 📋 What the Well-Architected Framework would say

L4 is the production upgrade of L3, and grading it against WAF is the point of
the lab — a real design review does exactly this.

| Pillar | How L4 scores |
|---|---|
| **Reliability** | ✅ Two regions, health-probed automatic failover, geo-replicated data, and a failover-group listener that survives promotion without a connection-string change. |
| **Operational Excellence** | ✅ The whole topology is one template. Front Door, the second region and the failover group deploy together or not at all. |
| **Performance Efficiency** | ✅ Front Door terminates at the edge and routes to the healthy origin. |
| **Cost Optimization** | ⚠️ The secondary runs warm at all times. Real DR balances that against your recovery-time objective. |
| **Security** | ❌ **The DR region has no private data path.** `sql-<prefix>-<suffix>-dr` disables public access but has no private endpoint, and the secondary app has no VNet integration. Test 3 above reports success while leaving the database unreachable. |

That last row is the lesson. Under WAF, a DR region you cannot reach privately
is not a DR region — a failover that "succeeds" into an unreachable database is
worse than no failover, because your monitoring says everything is fine.

**Close it yourself:** the second Copilot prompt in Option 3 adds the secondary
VNet, private DNS zone and private endpoint. That is the difference between a
lab that demonstrates multi-region and a design that would pass review.

<br>

---

## 🎉 You're done

Tear everything down when finished — Front Door, Firewall, Bastion and SQL all bill while idle:

```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP -WhatIf
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP
```

Then check **[Troubleshooting](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Troubleshooting)** and **[Tools and References](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Tools-and-References)** for going further.
