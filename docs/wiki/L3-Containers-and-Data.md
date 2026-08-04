# L3 — Containers, Data & Private Networking 🟠

**Goal:** modernize the app tier — Azure Container Apps instead of VMs, an Azure SQL backend, Key Vault + managed identity for secrets, Log Analytics/App Insights monitoring with an email alert. This is where **private networking** arrives: SQL and Key Vault have public access **disabled** and are only reachable through private endpoints.

```mermaid
flowchart LR
  YOU(["You"])
  HUB["vnet-iacdemo-hub<br/>from L1"]

  subgraph SPOKE2["vnet-iacdemo-spoke2 · 10.2.0.0/16 · NEW in L3"]
    subgraph ACA["snet-aca 10.2.0.0/23 · delegated to Microsoft.App"]
      APP["ca-iacdemo-web<br/>cae-iacdemo-l3<br/>public ingress<br/>managed identity"]
    end
    subgraph PE["snet-private-endpoints 10.2.2.0/24"]
      PESQL["private endpoint<br/>to SQL"]
      PEKV["private endpoint<br/>to Key Vault"]
    end
  end

  SQL["sql-iacdemo-xxxxxx<br/>Azure SQL Basic<br/>public access DISABLED"]
  KV["kv-iacdemo-xxxxxx<br/>Key Vault, RBAC<br/>public access DISABLED"]
  DNS["private DNS zones<br/>linked to spoke2 only"]
  MON["log-iacdemo-l3 + appi-iacdemo-l3<br/>alert: replicas >= 2 for 15 min"]

  SPOKE2 <-->|"VNet peering to L1's hub"| HUB
  YOU -->|"HTTPS, public ingress<br/>does NOT pass through the firewall"| APP
  APP --> PESQL --> SQL
  APP --> PEKV --> KV
  DNS -.->|"resolves privatelink names<br/>for workloads inside spoke2"| PE
  APP --> MON
  YOU -. "BLOCKED, public access disabled" .-> SQL

  classDef net fill:#eef4ff,stroke:#4472c4,color:#1a1a1a
  classDef compute fill:#eefaf0,stroke:#3a9d5d,color:#1a1a1a
  classDef data fill:#f5eefc,stroke:#7c4dbe,color:#1a1a1a
  classDef blocked fill:#fdecea,stroke:#c0392b,color:#1a1a1a
  class PESQL,PEKV,DNS,HUB net
  class APP,MON compute
  class SQL,KV data
```

<details><summary>Text description of this diagram</summary>

L3 creates a **second spoke** — `vnet-iacdemo-spoke2` (`10.2.0.0/16`) — and
peers it to L1's hub. It does not reuse L1's spoke, and it does not route
through L2's firewall: this stack branches off the hub on its own. L2 is not a
prerequisite.

The spoke holds two subnets. `snet-aca` (`10.2.0.0/23`) is delegated to
`Microsoft.App/environments` and runs the Container Apps environment and the
web app. `snet-private-endpoints` (`10.2.2.0/24`) holds one private endpoint
for SQL and one for Key Vault.

Both data services have **public network access disabled**, so a connection
from your laptop fails. The app reaches them over private endpoints using its
managed identity. The private DNS zones are what make that work — they resolve
the `privatelink` hostnames to private addresses, and they are linked to
**spoke2 only**, so the name resolves privately from inside that VNet and
nowhere else.

One thing worth being explicit about: the container app itself is **publicly
reachable** (`ingressExternal: true`). "Private networking" here applies to the
data tier, not the front door.

</details>

Files: [`labs/L3-containers/main.bicep`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/labs/L3-containers/main.bicep) · `main.bicepparam`

> ⚠️ **L1 must already be deployed** — L3 reuses the spoke network. L3 uses your **SQL** password (saved in L1's one-time block).

<br>

## 🚀 Deploy L3 — pick any one of three ways

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
az deployment group what-if --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L3-containers/main.bicepparam
az deployment group create  --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L3-containers/main.bicepparam
```

The output prints the app URL (`https://ca-<prefix>-web...azurecontainerapps.io`). *(The alert email comes from the `ALERT_EMAIL` column in `lab-settings.csv`.)*

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option 2 · GitHub Actions (push-button)

> [!TIP]
> **Best if you'd rather click a button.** Needs the one-time `Setup-Oidc.ps1` from L1.
> No `lab-settings.csv` needed — Actions uses the GitHub secrets from that setup.

On GitHub: **Actions → "Deploy L3 - Containers & Data" → Run workflow** (or `gh workflow run deploy-l3.yml`). Signs in with OIDC, runs Lint → What-if → Deploy.

<br>

---

## <img src="gh-copilot.png" width="30" align="top">&nbsp; Option 3 · GitHub Copilot (plain English)

> [!IMPORTANT]
> **Best if you'd rather describe the change** and have AI edit + deploy it.

Copilot runs the deploy **locally**, so load your values once first (same file as Option 1): `./scripts/Load-LabSettings.ps1`.

Open **Copilot Chat → Agent mode**:

> Deploy `labs/L3-containers/main.bicep` to my lab resource group (`$env:AZURE_RESOURCE_GROUP`) with `az deployment group create`.

**Want to scale it first?** Ask:

> In `labs/L3-containers/main.bicep`, raise `maxReplicas` to 5 and add an env var `GREETING=Hello L3` to the container, run `az bicep build`, then deploy.

Copilot edits, verifies, and deploys — and fixes any error you paste back.

<br>

---

## ✅ Test it (3 ways)

```powershell
$RG = $env:AZURE_RESOURCE_GROUP; $PREFIX = $env:AZURE_PREFIX
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

<br>

---

## ➡️ What carries forward

L4 treats this stack as the **primary region** — it adds a second-region copy, puts your SQL database in a failover group, and fronts both regions with Front Door. **Leave L3 deployed** → **[continue to L4](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/L4-Global-Scale)**.
