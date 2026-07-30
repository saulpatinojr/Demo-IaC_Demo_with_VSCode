# L3 — Containers, Data & Private Networking 🟠

**Goal:** modernize the app tier — Azure Container Apps instead of VMs, an Azure SQL backend, Key Vault + managed identity for secrets, Log Analytics/App Insights monitoring with an email alert. This is where **private networking** arrives: SQL and Key Vault have public access **disabled** and are only reachable through private endpoints.

![L3 containers and private networking](diagram-l3.svg)

Files: [`labs/L3-containers/main.bicep`](../blob/main/labs/L3-containers/main.bicep) + `main.bicepparam`

---

## Deploy the Bicep template

**L1 must already be deployed** (L3 reuses the spoke network). Same three commands — note L3 uses a **SQL** password, not the VM one.

### 1. Set your values (once per terminal)

```powershell
$RG                     = "rg-lab-<yourname>"
$env:AZURE_PREFIX       = "<yourname>"
$env:AZURE_LOCATION     = "eastus2"
$env:SQL_ADMIN_PASSWORD = "<Strong-Throwaway-Passw0rd!>"   # must NOT contain 'sqladminuser'
$env:ALERT_EMAIL        = "you@yourdomain.com"             # optional — used by the alert
```

### 2. Preview

```powershell
az deployment group what-if `
  --resource-group $RG `
  --parameters labs/L3-containers/main.bicepparam
```

### 3. Deploy

```powershell
az deployment group create `
  --resource-group $RG `
  --parameters labs/L3-containers/main.bicepparam
```

The deployment output prints the app URL (`https://ca-<prefix>-web...azurecontainerapps.io`).

> Prefer CI/CD? Same three stages run in the **GitHub Actions** workflow — see the [Deployment Guide](Deployment-Guide).

---

## Test it (3 ways)

1. **Hit the app** — open the printed URL; the quickstart page loads.
2. **Prove SQL is private-only** — from your laptop:
   ```powershell
   $SQL = az sql server list -g $RG --query "[?starts_with(name, 'sql-$env:AZURE_PREFIX-')].name | [0]" -o tsv
   nslookup "$SQL.database.windows.net"
   sqlcmd -S "$SQL.database.windows.net" -U sqladminuser -P $env:SQL_ADMIN_PASSWORD -Q "SELECT 1"
   ```
   The `sqlcmd` attempt from your laptop **fails** — public SQL access is disabled. From inside the VNet the same name resolves to a `10.2.2.x` private IP. That's private endpoints working.
3. **Monitoring + alert** — scale the app and watch for the "HighReplicaCount" alert email (~15 min), or query Log Analytics:
   ```powershell
   az containerapp update -n "ca-$env:AZURE_PREFIX-web" -g $RG --min-replicas 2
   ```

---

> ### <img src="copilot-logo.png" width="24" align="top">&nbsp; GitHub Copilot — the alternative path
>
> Prefer to **let Copilot drive**? Open **Copilot Chat → Agent mode**:
>
> > _Deploy `labs/L3-containers/main.bicep` to resource group `rg-lab-<yourname>` with `az deployment group create` using prefix `<yourname>`, and prompt me for the SQL admin password._
>
> **Why reach for Copilot here?**
> - **Scale + configure before deploy** — _"raise `maxReplicas` to 5 and add an env var `GREETING=Hello L3` to the container, then redeploy"_.
> - **Add observability** — _"add a metric alert when the SQL database CPU averages over 80% for 15 minutes, reusing the existing action group"_.
> - **Explain private networking** — _"how do the private endpoints and DNS zones make SQL reachable only from the VNet?"_
>
> Copilot edits the Bicep, runs `az bicep build`, and reruns the deploy for you.

---

## What carries forward

L4 treats this stack as the **primary region** — it adds a second-region copy, puts your SQL database in a failover group, and fronts both regions with Front Door. **Leave L3 deployed** → [continue to L4](L4-Global-Scale).
