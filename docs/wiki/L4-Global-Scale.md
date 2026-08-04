# L4 — Global Scale 🔴

**Goal:** the production upgrade of L3 — survive a regional outage. A second-region app stack in `westus2`, an **Azure SQL failover group**, and **Azure Front Door** as the single global entry point with health-probed failover. Then grade the result against the Well-Architected Framework, the way a real design review would.

| Who this is for | Time | You need first | Cost while it runs |
|---|---|---|---|
| Lab 4 of 4 · everyone | ~15 min, plus ~10 for Front Door to propagate | L3 deployed | 🔴 ~$1.84/hr running total |

> [!IMPORTANT]
> **L3 must already be deployed.** L4 joins L3's SQL server to a failover group, and uses the **same** `SQL_ADMIN_PASSWORD` — a failover group requires matching logins on both servers.

## What you're building

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

**Source:** [`labs/L4-global/main.bicep`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/labs/L4-global/main.bicep) · [`labs/modules/sql-failover-group.bicep`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/labs/modules/sql-failover-group.bicep)

> [!NOTE]
> **The secondary region is deliberately slim.** It has no VNet integration, no Key Vault and no Application Insights, and the DR database has no private endpoint. That is a teaching choice, not an oversight — it keeps the lab affordable and gives you something concrete to fix. The [Well-Architected scorecard](#-what-the-well-architected-framework-would-say) at the end of this page is where that bill comes due.

<br>

## 🚀 Deploy it — pick any one of three ways

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

**Best if you like the command line.** Your values are already loaded from `lab-settings.csv` (set up in L1) — nothing to re-type.

```powershell
az deployment group what-if --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L4-global/main.bicepparam
az deployment group create  --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L4-global/main.bicepparam
```

**You should see:** a `frontDoorEndpoint` output — a full URL including `https://`. The deployment finishes before Front Door is actually serving; allow about ten more minutes for the edge to propagate before test 1 succeeds.

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option 2 · GitHub Actions (push-button)

**Best if you'd rather click a button.** Needs the one-time `Setup-Oidc.ps1` from L1 — and no `lab-settings.csv`, because Actions reads the GitHub secrets instead.

On GitHub: **Actions → "Deploy L4 - Global Scale" → Run workflow** (or `gh workflow run deploy-l4.yml`).

**You should see:** **Lint → What-if → Deploy**, then a final step printing the Front Door endpoint.

<br>

---

## <img src="gh-copilot.png" width="30" align="top">&nbsp; Option 3 · GitHub Copilot (plain English)

**Best if you'd rather describe the change** and have AI edit and deploy it.

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

## ✅ Verify it

Fetch the Front Door hostname rather than typing it — the endpoint name has a generated hash you can't guess:

```powershell
$FDE = az afd endpoint list -g $env:AZURE_RESOURCE_GROUP `
  --profile-name (az afd profile list -g $env:AZURE_RESOURCE_GROUP --query "[0].name" -o tsv) `
  --query "[0].hostName" -o tsv
"https://$FDE/"
```

**You should see:** a hostname like `fde-yourprefix-a1b2c3.z01.azurefd.net`, with **no** scheme. The deployment output includes `https://` already, so pasting that into `$FDE` instead would give you `https://https://…`.

1. **Traffic reaches the primary through Front Door**

   ```powershell
   curl.exe -sI "https://$FDE/"
   ```

   **You should see:** `HTTP/2 200`. If you get a 4xx or a connection error, Front Door is still propagating — wait a few minutes and retry.

2. **Failing the primary moves traffic to the secondary** — deactivate the *active* revision, not just the first one listed:

   ```powershell
   $APP = "ca-$env:AZURE_PREFIX-web"
   $REVISION = az containerapp revision list -g $env:AZURE_RESOURCE_GROUP -n $APP `
     --query "[?properties.active].name | [0]" -o tsv
   az containerapp revision deactivate -g $env:AZURE_RESOURCE_GROUP -n $APP --revision $REVISION
   curl.exe -s "https://$FDE/"
   ```

   **You should see:** the endpoint keep responding after 30–90 seconds, once the health probes mark the primary down. Front Door has switched to the `westus2` origin. The page looks identical because both regions run the same image.

   **Then put it back:**

   ```powershell
   az containerapp revision activate -g $env:AZURE_RESOURCE_GROUP -n $APP --revision $REVISION
   ```

3. **The database has a listener that survives failover** — this, not the server names, is what an application should connect to:

   ```powershell
   $PRIMARY_SQL = az sql server list -g $env:AZURE_RESOURCE_GROUP `
     --query "[?starts_with(name, 'sql-$env:AZURE_PREFIX-') && !ends_with(name, '-dr')].name | [0]" -o tsv
   $FOG = az sql failover-group list -g $env:AZURE_RESOURCE_GROUP --server $PRIMARY_SQL --query "[0].name" -o tsv
   az sql failover-group show -g $env:AZURE_RESOURCE_GROUP --server $PRIMARY_SQL --name $FOG `
     --query "{listener:name, role:replicationRole, partners:partnerServers[].id}" -o yaml
   ```

   **You should see:** the group's `replicationRole` as `Primary`. Its listener is `<group-name>.database.windows.net` — point a connection string at that and it follows whichever server is currently primary, with no change on failover.

4. **Fail the database over, and back**

   ```powershell
   $DR_SQL = az sql server list -g $env:AZURE_RESOURCE_GROUP `
     --query "[?starts_with(name, 'sql-$env:AZURE_PREFIX-') && ends_with(name, '-dr')].name | [0]" -o tsv
   az sql failover-group set-primary -g $env:AZURE_RESOURCE_GROUP --server $DR_SQL --name $FOG
   ```

   **You should see:** the command succeed, and re-running test 3 report `Secondary` for the original server. Fail back by running `set-primary` against `$PRIMARY_SQL`.

   > [!WARNING]
   > This one succeeds while leaving you worse off, and that is the point. The DR server has public access disabled and **no private endpoint**, so nothing can actually reach the database you just promoted. The scorecard below explains why, and the Copilot prompt above fixes it.

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
| **Security** | ❌ **The DR region has no private data path.** `sql-<prefix>-<suffix>-dr` disables public access but has no private endpoint, and the secondary app has no VNet integration. Test 4 above reports success while leaving the database unreachable. |

That last row is the lesson. Under WAF, a DR region you cannot reach privately
is not a DR region — and a failover that "succeeds" into an unreachable database
is worse than no failover at all, because every dashboard says you are fine.

**Close it yourself:** the second Copilot prompt in Option 3 adds the secondary
VNet, private DNS zone and private endpoint. That is the difference between a
lab that demonstrates multi-region and a design that would pass review.

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Traceable deployments**
>
> **You just used it:** every deployment this repo creates is named with the run that produced it — `l4-deploy-42` comes from GitHub Actions run number 42. Azure's deployment history and your CI history share a key.
> **Find it:** `az deployment group list -g $env:AZURE_RESOURCE_GROUP --query "[].name" -o tsv`, then open that run number in the **Actions** tab to see exactly what was deployed, by whom, from which commit.
> **Beyond the lab:** during an incident, "which change did this?" becomes one lookup instead of an archaeology session. It costs one line of YAML: `--name l4-deploy-${{ github.run_number }}`.
> [Docs →](https://docs.github.com/actions/learn-github-actions/contexts#github-context)

<br>

---

## ➡️ What carries forward

You have built the whole stack. Two things are worth doing next.

**Close the WAF gap.** The Copilot prompt in Option 3 gives the DR region a real
data path. It is the most realistic exercise in the workshop, because you are
fixing a design rather than following instructions.

**Then tear it down.** Front Door, Firewall, Bastion and SQL all bill while
idle — about **$1.84/hr** with everything running. Preview first:

```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP -WhatIf
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP
```

> [!CAUTION]
> The second command deletes every resource in the group and prompts for confirmation. It leaves the resource group itself in place, which is what you want in a classroom — you usually can't recreate it.

Stuck on anything, or curious where to go next? **[Troubleshooting](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Troubleshooting)** · **[Tools and References](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Tools-and-References)**
