# L2.3 — Proactive Operations 🔵

**📍 [Level 2 · Monitor](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-2-Monitor)** · Chapter 3 of 4 &nbsp;·&nbsp; Previous: [L2.2 — Operational Visibility](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-2-Operational-Visibility) &nbsp;·&nbsp; Next: [L2.4 — Enterprise Monitoring Strategy](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-4-Monitoring-Strategy)

---

**Goal:** stop having to look. Six alert rules watch the estate — CPU, database,
firewall, dead VMs, error spikes and Azure itself — and mail one inbox when
something needs a human.

**The IaC lesson:** alert rules are resources. Thresholds, evaluation windows
and inboxes all live in the template — reviewed, versioned and identical for
every classroom — not in portal clicks nobody can audit.

<br>

| Who this is for | Time | You need first | Cost while it runs |
|---|---|---|---|
| Chapter 3 of Level 2 · everyone | ~20 min | **L2.1** and **L2.2** | 🔵 ~$0.01/hr added · ~$1.93/hr running total |

> [!IMPORTANT]
> This chapter creates its **own** action group. It does not edit the one L1.3
> created — two templates owning one resource means whichever deployed last
> wins. Adding a resource is cheap; sharing ownership is not.

<br>

## What you're building

Three kinds of signal feed six rules, and every rule notifies the same action
group. A processing rule silences the lot during the nightly maintenance
window.

```mermaid
flowchart LR
  MET["platform metrics<br/>free, already there"]
  LOGS["log data<br/>from L2.1"]
  SVC["Azure Service Health"]
  RULES["6 alert rules<br/>3 metric · 2 log · 1 service health"]
  AG["ag-iacdemo-oncall<br/>primary + secondary inbox"]
  APR["processing rule<br/>02:00–03:00 UTC<br/>suppress everything"]

  MET --> RULES
  LOGS --> RULES
  SVC --> RULES
  RULES --> AG
  APR -.->|"mutes during<br/>the window"| AG

  classDef sig fill:#eef4ff,stroke:#4472c4,color:#1a1a1a
  classDef rule fill:#fff9e6,stroke:#c9a227,color:#1a1a1a
  classDef act fill:#eefaf0,stroke:#3a9d5d,color:#1a1a1a
  class MET,LOGS,SVC sig
  class RULES rule
  class AG,APR act
```

<details><summary>Text description of this diagram</summary>

Three signal sources feed six rules, which all notify one action group.

**Platform metrics** — free, already collected — drive three metric alerts:
CPU above 80% across every VM as one multi-resource rule, a dynamic-threshold
rule on SQL DTU, and SNAT port utilisation on the firewall.

**Log data from L2.1** drives two scheduled query rules. These catch what
metrics structurally cannot: a VM that stopped reporting emits no metric to
threshold, so only a query over `Heartbeat` can notice its absence.

**Service Health** drives a free activity-log alert — the only rule here that
fires for something you cannot fix, which is exactly why you want it before
you spend an hour debugging your own template.

Everything notifies `ag-iacdemo-oncall`. The dotted line is the alert
processing rule: between 02:00 and 03:00 UTC it strips the action groups off
every alert in the resource group, so maintenance does not page anyone.

</details>

**Source:** [`curriculum/L2.3-proactive-operations/main.bicep`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/curriculum/L2.3-proactive-operations/main.bicep) · [`main.bicepparam`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/curriculum/L2.3-proactive-operations/main.bicepparam)

<br>

<details><summary><b>🔍 Going deeper — where is autoscale?</b></summary>

<br>

The learning objective is real, but this estate has nowhere honest to put it.
Azure Monitor autoscale targets virtual machine scale sets and App Service
plans; the only elastic thing here is the container app, and its scale rules
live inside `curriculum/L1.3-multi-service-application/main.bicep` — the
template that owns it. Adding them from this chapter would recreate exactly
the shared-ownership problem the callout above warns about. Read the scale
block in L1.3's template instead, and change it there.

</details>

<details><summary><b>🔍 Going deeper — the permissions this needs</b></summary>

<table>
<tr>
<td width="72" align="center" valign="top"><img src="icon-azure-rbac.svg" width="44"></td>
<td valign="top">
<b>Azure RBAC</b><br><br>
<b>Contributor</b>, or <b>Monitoring Contributor</b> on the lab resource group.<br>
<sub>Why: alert rules, action groups and processing rules are all ordinary resources. The Service Health alert is scoped to the <b>subscription</b> and needs read access there — with resource-group-only rights it will fail, which is the first place this lab's permission ceiling shows up.</sub>
</td>
</tr>
<tr>
<td width="72" align="center" valign="top"><img src="icon-entra-id.svg" width="44"></td>
<td valign="top">
<b>Microsoft Entra ID roles</b><br><br>
<b>None.</b><br>
<sub>Email receivers are plain addresses, not directory objects.</sub>
</td>
</tr>
</table>

<sub><a href="https://learn.microsoft.com/azure/azure-monitor/roles-permissions-security">For more info</a> — Azure Monitor roles, permissions and security</sub>

</details>

<br>

---

> [!NOTE]
> **🏫 Classroom: use the GitHub Actions option.** Your Azure account holds Reader, so local `az deployment` commands will be refused — deploys go through your fork's workflow, which uses the shared workshop identity automatically. Compiling locally (`az bicep build`) works for everyone.

## 🚀 Deploy it — pick any one of three ways

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

```powershell
az deployment group what-if --resource-group $env:AZURE_RESOURCE_GROUP --parameters curriculum/L2.3-proactive-operations/main.bicepparam
az deployment group create  --resource-group $env:AZURE_RESOURCE_GROUP --parameters curriculum/L2.3-proactive-operations/main.bicepparam
```

**You should see:** `metricAlertCount` 3, `logAlertCount` 2, and a
`monthlyAlertCostBasis` string spelling out what you just signed up for.

**Want a second inbox?** Set it before deploying:

```powershell
$env:ALERT_EMAIL_SECONDARY = "someone.else@example.com"
```

<br>

---

## <img src="gh-actions.png" width="30" align="top">&nbsp; Option 2 · GitHub Actions (push-button)

**Actions → "Curriculum L2 - Operations & Monitoring" → Run workflow →
L2.3 - Proactive Operations**.

The addresses come from repository variables `ALERT_EMAIL` and
`ALERT_EMAIL_SECONDARY` — the first is the same one the L1.3 lab already uses,
so a class that set it once does not set it again.

<br>

---

## <img src="gh-copilot.png" width="30" align="top">&nbsp; Option 3 · GitHub Copilot (plain English)

Load your values first: `./scripts/Load-LabSettings.ps1`. Then in
**Copilot Chat → Agent mode**:

> Deploy `curriculum/L2.3-proactive-operations/main.bicep` to my lab resource group (`$env:AZURE_RESOURCE_GROUP`) with `az deployment group create`.

**Turn one of L2.2's saved queries into a rule:**

> In `curriculum/L2.3-proactive-operations/main.bicep`, add a scheduled query rule that fires when the firewall denies more than 50 flows in 15 minutes, using the same query as the `firewall-verdicts` saved search in L2.2. Keep the evaluation frequency at PT15M. Run `az bicep build`, then show me a what-if.

Notice what you had to decide: a threshold, a window, and whether it is worth
$0.50 a month. Every one of those is a judgement, not a lookup.

<br>

---

## ✅ Verify it

1. **The rules exist and are enabled:**

   ```powershell
   az monitor metrics alert list -g $env:AZURE_RESOURCE_GROUP -o table
   az monitor scheduled-query list -g $env:AZURE_RESOURCE_GROUP -o table
   ```

   **You should see:** three metric rules (two if you skipped L1.2) and two
   scheduled query rules.

2. **Make one fire** — load a VM through Bastion and wait for the window:

   ```bash
   sudo apt-get install -y stress-ng && stress-ng --cpu 2 --timeout 900s
   ```

   **You should see:** the CPU rule move to *Fired* within about 15 minutes,
   and mail at your alert address. The rule averages over 15 minutes on
   purpose — a one-minute spike is not an incident.

3. **Prove the log alert catches what metrics cannot** — stop a VM entirely:

   ```powershell
   az vm deallocate -g $env:AZURE_RESOURCE_GROUP -n "vm-$env:AZURE_PREFIX-web2"
   ```

   **You should see:** *A VM stopped reporting* fire within about 15 minutes.
   The CPU metric rule stays silent throughout — a VM that is gone emits no
   metric to threshold. That difference is the whole reason both rule types
   exist. Start it again with `az vm start` afterwards.

4. **Check the suppression window is real:**

   ```powershell
   az monitor alert-processing-rule list -g $env:AZURE_RESOURCE_GROUP -o table
   ```

   **You should see:** `apr-<prefix>-maintenance-window`, enabled, 02:00–03:00
   UTC. Worth saying out loud: during that hour, genuine alerts are swallowed
   too. Suppression is a governance decision, not a convenience.

5. **What it costs:** metric alerts bill $0.10 per monitored metric per month;
   log alerts are $0.50 each at 15-minute evaluation. The set above is about
   **$2.30/month**. Service Health and the processing rule are free.

<br>

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Repository variables as the notification path**
>
> **You just used it:** `ALERT_EMAIL` and `ALERT_EMAIL_SECONDARY` are repository
> variables, not values baked into a template. The same Bicep deploys to a class
> of thirty people and pages thirty different inboxes.
> **Find it:** **Settings → Secrets and variables → Actions → Variables**. Note
> which one is *not* a secret — an email address is configuration, and treating
> it as a secret would only make it harder to review.
> **Beyond the lab:** the boundary between "secret" and "variable" is the same
> boundary as "who can see the audit log" — get it wrong in either direction and
> something either leaks or becomes unreviewable.
> [Docs →](https://docs.github.com/actions/learn-github-actions/variables#defining-configuration-variables-for-multiple-workflows)

<br>

---

## ➡️ What carries forward

L2.4 asks the governing question: which of these rules would you keep if you
ran a hundred of these environments, and what would you stop collecting? It is
the first chapter in the curriculum designed to *reduce* the bill.

<br>

## 🧭 Where next?

| Your situation | Go to |
|---|---|
| Ready to keep going — make the bill smaller | **[L2.4 — Enterprise Monitoring Strategy](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-4-Monitoring-Strategy)** |
| ⬅ Back to the main path | [🗺️ Curriculum Map](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Map) |
| Want the big picture of this level | [Level 2 · Monitor overview](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-2-Monitor) |
| Done for the day — the estate bills while idle | [Cleanup & Reset](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Cleanup-and-Reset) |
| Something didn't work | [Troubleshooting](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Troubleshooting) |
