# L3 — Containers, Data & Private Networking 🟠

**Goal:** modernize the app tier — Azure Container Apps instead of VMs, an Azure SQL backend, Key Vault + managed identity for secrets, Log Analytics/App Insights monitoring with an email alert. This is where **private networking** arrives: SQL and Key Vault have public access **disabled** and are only reachable through private endpoints.

![L3 containers and private networking](diagram-l3.svg)

Files: [`labs/L3-containers/main.bicep`](../blob/main/labs/L3-containers/main.bicep) + `main.bicepparam`

---

## Deploy the Bicep template

**L1 must already be deployed** (L3 reuses the spoke network). L3 uses the **SQL** password — also stored once by `Setup-Oidc.ps1`, so there's **nothing to paste**.

### 1. (Optional) confirm setup

```powershell
gh secret list      # expect SQL_ADMIN_PASSWORD among the others
gh variable list    # expect AZURE_PREFIX, AZURE_LOCATION (and optionally ALERT_EMAIL)
```

Missing `ALERT_EMAIL` and want the alert email? Re-run with it:
`./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>" -AlertEmail "you@yourdomain.com"`

### 2. Run the deploy

GitHub → **Actions → "Deploy L3 - Containers & Data" → Run workflow** (or `gh workflow run deploy-l3.yml`). Lint → What-if → Deploy. The run output prints the app URL (`https://ca-<prefix>-web...azurecontainerapps.io`).

---

## Test it (3 ways)

```powershell
$RG = "rg-lab-<yourname>"; $PREFIX = "<yourname>"
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
> > _In `labs/L3-containers/main.bicep`, raise `maxReplicas` to 5 and add an env var `GREETING=Hello L3` to the container, run `az bicep build`, then commit, push, and trigger `gh workflow run deploy-l3.yml`._
>
> **Why reach for Copilot here?**
> - **Scale + configure before deploy** — the prompt above edits, verifies, and redeploys in one shot.
> - **Add observability** — _"add a metric alert when the SQL database CPU averages over 80% for 15 minutes, reusing the existing action group"_.
> - **Explain private networking** — _"how do the private endpoints and DNS zones make SQL reachable only from the VNet?"_
>
> No creds to handle — the workflow logs in with OIDC using your stored secrets.

---

## What carries forward

L4 treats this stack as the **primary region** — it adds a second-region copy, puts your SQL database in a failover group, and fronts both regions with Front Door. **Leave L3 deployed** → [continue to L4](L4-Global-Scale).
