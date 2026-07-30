# L3 — Containers, Data & Private Networking 🟠

**Goal:** modernize the app tier — Azure Container Apps instead of VMs, an Azure SQL backend, Key Vault + managed identity for secrets, Log Analytics/App Insights monitoring with an email alert. This is where **private networking** arrives: SQL and Key Vault have public access **disabled** and are only reachable through private endpoints.

![L3 containers and private networking](diagram-l3.svg)

Files: [`labs/L3-containers/main.bicep`](../blob/main/labs/L3-containers/main.bicep) + `main.bicepparam`

---

## Deploy the Bicep template

**L1 must already be deployed** (L3 reuses the spoke network). L3 uses your **SQL** password — already saved by L1's one-time block. Set your resource group and run the two commands:

```powershell
$RG = "rg-lab-<yourname>"
az deployment group what-if --resource-group $RG --parameters labs/L3-containers/main.bicepparam
az deployment group create  --resource-group $RG --parameters labs/L3-containers/main.bicepparam
```

> Want the alert email? Set it once: `[Environment]::SetEnvironmentVariable('ALERT_EMAIL','you@yourdomain.com','User'); $env:ALERT_EMAIL='you@yourdomain.com'`

The deployment output prints the app URL (`https://ca-<prefix>-web...azurecontainerapps.io`).

> ### ⚙️ GitHub Actions — the hands-off alternative
> After the one-time OIDC setup (see the [Deployment Guide](Deployment-Guide)): GitHub → **Actions → "Deploy L3 - Containers & Data" → Run workflow** (or `gh workflow run deploy-l3.yml`). Logs in with OIDC, runs Lint → What-if → Deploy, no local input.

---

## Test it (3 ways)

```powershell
$RG = "rg-lab-<yourname>"; $PREFIX = $env:AZURE_PREFIX
```

1. **Hit the app** — open the printed URL; the quickstart page loads.
2. **Prove SQL is private-only** — from your laptop:
   ```powershell
   $SQL = az sql server list -g $RG --query "[?starts_with(name, 'sql-$PREFIX-')].name | [0]" -o tsv
   nslookup "$SQL.database.windows.net"
   ```
   Connecting to that SQL server from your laptop **fails** — public access is disabled. From inside the VNet the same name resolves to a `10.2.2.x` private IP. That's private endpoints working.
3. **Monitoring + alert** — scale the app and watch for the "HighReplicaCount" alert email (~15 min):
   ```powershell
   az containerapp update -n "ca-$PREFIX-web" -g $RG --min-replicas 2
   ```

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Prefer to **let Copilot drive**? Open **Copilot Chat → Agent mode**:
>
> > _In `labs/L3-containers/main.bicep`, raise `maxReplicas` to 5 and add an env var `GREETING=Hello L3` to the container, run `az bicep build`, then deploy with `az deployment group create --resource-group rg-lab-<yourname> --parameters labs/L3-containers/main.bicepparam`._
>
> **Why reach for Copilot here?**
> - **Scale + configure before deploy** — the prompt above edits, verifies, and redeploys in one shot.
> - **Add observability** — _"add a metric alert when the SQL database CPU averages over 80% for 15 minutes, reusing the existing action group"_.
> - **Explain private networking** — _"how do the private endpoints and DNS zones make SQL reachable only from the VNet?"_

---

## What carries forward

L4 treats this stack as the **primary region** — it adds a second-region copy, puts your SQL database in a failover group, and fronts both regions with Front Door. **Leave L3 deployed** → [continue to L4](L4-Global-Scale).
