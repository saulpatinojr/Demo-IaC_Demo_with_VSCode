# Curriculum Cost Model 💰

Every figure on the six level pages of the
**[Curriculum Redesign](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Redesign)**
is derived here. This page holds the unit rates, the assumptions behind the
usage-based lines, the cost categories tracked across the whole curriculum, and
the optimization levers available at each stage.

> [!IMPORTANT]
> **Planning estimates, not a quote.** East US 2 (West US 2 for the secondary
> region), US retail pay-as-you-go rates. Rates marked *Verified 2026-08-08* came
> back from the Azure Retail Prices API on that date; rates marked
> *Repo 2026-08-04* are the existing lab rates in `unit cost/Build-CostDocs.ps1`.
> Your invoice will differ under an EA, CSP or MCA agreement.

## The ten cost categories

These are the categories the curriculum should track and label at every chapter.
Each behaves differently, and confusing them is the most common budgeting
mistake in Azure.

| # | Category | Billing shape | Introduced at | Controlled by |
|---|---|---|---|---|
| 1 | **Always-on infrastructure** | Per hour, while deployed | L1.1 | Deleting it. Nothing else. |
| 2 | **Network & data processing** | Per GB moved or inspected | L1.2 | Traffic volume, egress zone |
| 3 | **Standby & redundancy premium** | Per hour, delivers nothing on a normal day | L1.4 | Architecture choice |
| 4 | **Telemetry ingestion** | Per GB ingested | L2.1 | What you collect, and into which table plan |
| 5 | **Telemetry retention & archive** | Per GB-month | L2.4 | Retention period, tier |
| 6 | **Alerting & automation** | Per rule-month, per action | L2.3 | Rule count and evaluation frequency |
| 7 | **Per-node protection plans** | Per node/instance-month | L3.2 | Node count, plan tier, enablement scope |
| 8 | **Backup & recovery storage** | Per GB-month × redundancy | L4.1 | Retention × redundancy × instances |
| 9 | **Security analytics** | Per GB analysed | L5.1 | Connector selection, table plan |
| 10 | **Event & drill costs** | Per event, transient | L4.3, L6.3 | Frequency, and cleaning up afterwards |

Three properties are worth teaching explicitly:

- **Categories 1 and 3 bill while idle.** They are the only ones a teardown
  fully removes, and the only ones that cost money overnight for nothing.
- **Categories 4, 5, 8 and 9 accumulate.** They grow with time even when the
  architecture is frozen, which is why they are the most commonly
  under-forecast lines in a real bill.
- **Category 8 survives teardown.** Deleting a VM does not delete its recovery
  points.

## Unit rates

### Infrastructure — reused from the existing lab cost model

| Resource | Rate | Basis |
|---|---|---|
| Linux VM `Standard_B2s` | $0.0416/hr | Repo 2026-08-04, verified |
| OS disk, Standard HDD S4 (32 GiB) | $0.0021/hr | Repo 2026-08-04, list |
| Azure Bastion Basic | $0.19/hr | Repo 2026-08-04, verified |
| Standard public IP | $0.005/hr | Repo 2026-08-04, list |
| Azure Firewall Standard, deployment | $1.25/hr | Verified 2026-08-08 |
| Azure Firewall Standard, capacity unit | $0.07/hr | Verified 2026-08-08 |
| Azure Firewall, data processed | $0.016/GB | Verified 2026-08-08 |
| Standard Load Balancer (first 5 rules) | $0.025/hr | Repo 2026-08-04, list |
| Container Apps replica, 0.5 vCPU + 1 GiB | $0.054/hr | Repo 2026-08-04, verified |
| Azure SQL Database Basic (5 DTU) | $0.0067/hr | Repo 2026-08-04, verified |
| Private endpoint | $0.01/hr | Repo 2026-08-04, list |
| Private DNS zone | $0.0007/hr | Repo 2026-08-04, list |
| Front Door Standard, base fee | $35/mo ($0.0479/hr) | Repo 2026-08-04, list |

### Premium tiers — priced so they can be declined with evidence

| Resource | Rate | Basis |
|---|---|---|
| Azure Firewall Basic, deployment | $0.395/hr | Verified 2026-08-08 |
| Azure Firewall Premium, deployment | $1.75/hr | Verified 2026-08-08 |
| Azure Firewall Premium, capacity unit | $0.11/hr | Verified 2026-08-08 |
| Front Door Premium, base fee (required for WAF managed rules) | $330/mo ($0.4521/hr) | Verified 2026-08-08 |
| Front Door Standard, data transfer out | $0.13–0.25/GB by zone | Verified 2026-08-08 |

### Monitoring and observability

| Meter | Rate | Basis |
|---|---|---|
| Log Analytics, Analytics tier ingestion | $2.76/GB | Verified 2026-08-08 |
| Log Analytics, Basic logs ingestion | $0.50/GB | Verified 2026-08-08 |
| Log Analytics, Auxiliary logs ingestion | $0.05/GB | Verified 2026-08-08 |
| Interactive retention beyond the included period | $0.12/GB/month | Verified 2026-08-08 |
| Archive (long-term retention) | $0.02/GB/month | Verified 2026-08-08 |
| Data restore from archive | $0.10/GB/day | Verified 2026-08-08 |
| Metric alert rule | $0.10/monitored metric/month | Verified 2026-08-08 |
| Log alert rule, 5-minute evaluation | $1.50/rule/month | Verified 2026-08-08 |
| Log alert rule, 15-minute evaluation | $0.50/rule/month | Verified 2026-08-08 |
| Standard availability test | $0.0005/execution | Verified 2026-08-08 |
| Multi-step web test | $10/month | Verified 2026-08-08 |
| Azure Activity log into Log Analytics | free | Verified 2026-08-08 |
| Platform metrics | free | Verified 2026-08-08 |

### Security — Microsoft Defender for Cloud

| Plan | Rate | Per-month equivalent | Basis |
|---|---|---|---|
| Defender CSPM (paid) | $0.007/resource/hr | ~$5.11 | Verified 2026-08-08 |
| Defender for Servers Plan 1 | $0.00672/node/hr | ~$4.91 | Verified 2026-08-08 |
| Defender for Servers Plan 2 | $0.02/node/hr | ~$14.60 | Verified 2026-08-08 |
| Defender for SQL | $0.020161/instance/hr | ~$14.72 | Verified 2026-08-08 |
| Defender for Key Vault | $0.00034/node/hr | ~$0.25 | Verified 2026-08-08 |
| Defender for Resource Manager | $0.0069/node/hr | ~$5.04 | Verified 2026-08-08 |
| Defender for Storage | $0.0134/account/hr | ~$9.78 | Verified 2026-08-08 |
| Defender for Containers | $0.00941/vCore/hr | ~$6.87 | Verified 2026-08-08 |
| Foundational CSPM, secure score, recommendations | free | — | Verified 2026-08-08 |

> [!NOTE]
> Defender for Containers protects AKS, Arc-enabled Kubernetes and registry
> images. It does **not** provide runtime protection for Azure Container Apps,
> so the L1.3 workload is covered by CSPM posture rather than by a workload
> plan. The rate is listed for completeness and for the architecture discussion
> in L3.2, not because the curriculum enables it.

### Security analytics — Microsoft Sentinel

| Meter | Rate | Basis |
|---|---|---|
| Sentinel pay-as-you-go analysis | $4.76/GB | Verified 2026-08-08 |
| Combined with Log Analytics ingestion | **~$7.52/GB** | Derived |
| Sentinel Basic logs analysis | $1.00/GB | Verified 2026-08-08 |
| Sentinel Auxiliary logs analysis | $0.05/GB | Verified 2026-08-08 |
| 100 GB/day commitment tier | $296/day | Verified 2026-08-08 |
| Free trial | first 10 GB/day free for 31 days | Microsoft Learn |
| Free data sources | $0 | Microsoft Learn |

Free data sources include Azure Activity, Microsoft Sentinel health,
Office 365 audit, and security alerts from Microsoft Defender XDR and Defender
for Cloud. Microsoft Entra ID sign-in and audit logs are **paid**.

### Backup and disaster recovery

| Meter | Rate | Basis |
|---|---|---|
| Azure VM protected instance | $10/month | Verified 2026-08-08 |
| Backup storage, LRS | $0.0224/GB/month | Verified 2026-08-08 |
| Backup storage, ZRS | $0.0280/GB/month | Verified 2026-08-08 |
| Backup storage, GRS | $0.0448/GB/month | Verified 2026-08-08 |
| Backup storage, RA-GRS (cross-region restore) | $0.0569/GB/month | Verified 2026-08-08 |
| Backup archive tier, LRS | $0.0027/GB/month | Verified 2026-08-08 |
| Blob / ADLS vaulted protected instance | $10/month | Verified 2026-08-08 |
| Azure Files protected instance | $5/month | Verified 2026-08-08 |
| SQL long-term retention storage, LRS | $0.025/GB/month | Verified 2026-08-08 |
| SQL long-term retention storage, RA-GRS | $0.05/GB/month | Verified 2026-08-08 |
| Azure Site Recovery, VM replicated to Azure | $25/month | Verified 2026-08-08 |
| Azure Chaos Studio, Essential | $0.10/action-minute | Verified 2026-08-08 |
| Soft delete, purge protection, immutable vault, MUA | free | Microsoft Learn |

## Usage assumptions

Every usage-based figure on the level pages comes from one of these. They are
deliberately conservative for a small teaching estate.

| Assumption | Value | Used by |
|---|---|---|
| Estate size | 4 × B2s VMs, 1 firewall, 1 load balancer, 2 container replicas, 2 SQL databases, 1 Key Vault, 1 Front Door | All levels |
| Baseline platform + VM insights ingestion | 0.5 GB/day | L2.1 |
| Application Insights telemetry | 0.15 GB/day | L2.2 |
| Availability test cadence | 2 locations every 15 min = 8 executions/hr | L2.2 |
| Alert rule set | 10 metric + 4 log rules at 5-minute evaluation | L2.3 |
| Security export and security events | 0.25 GB/day | L3.3 |
| Backup data stored | ~40 GB (4 VMs, compressed OS disks) | L4.1, L4.4 |
| Backup job telemetry | 0.05 GB/day | L4.3 |
| Sentinel paid connector volume | 1.0 GB/day | L5.1 |
| UEBA behaviour analytics | 0.1 GB/day | L5.2 |
| Logic Apps playbook actions | a few thousand per month | L3.3, L5.3 |
| VMs run continuously; nothing is deallocated | — | All levels |

## Full cost progression

Running totals assume everything from earlier chapters is still deployed.

| Chapter | Adds | Running total |
|---|---|---|
| L1.1 Core Deployment | +$0.24/hr | **$0.24/hr** |
| L1.2 Architecture Expansion | +$1.41/hr | **$1.65/hr** |
| L1.3 Multi-Service Application | +$0.08/hr | **$1.73/hr** |
| L1.4 Production-Ready Platform | +$0.11/hr | **$1.84/hr** |
| L2.1 Monitoring Fundamentals | +$0.06/hr | **$1.90/hr** |
| L2.2 Operational Visibility | +$0.02/hr | **$1.92/hr** |
| L2.3 Proactive Operations | +$0.01/hr | **$1.93/hr** |
| L2.4 Enterprise Monitoring Strategy | −$0.02/hr net | **$1.91/hr** |
| L3.1 Security Foundation | +$0.00/hr | **$1.91/hr** |
| L3.2 Workload Protection | +$0.07/hr | **$1.98/hr** |
| L3.3 Security Operations | +$0.03/hr | **$2.01/hr** |
| L3.4 Enterprise Security Architecture | +$0.00/hr as designed | **$2.01/hr** |
| L4.1 Backup Fundamentals | +$0.06/hr | **$2.07/hr** |
| L4.2 PaaS Protection | +$0.01/hr | **$2.08/hr** |
| L4.3 Operational Backup Management | +$0.01/hr | **$2.09/hr** |
| L4.4 Enterprise Data Protection | +$0.01/hr | **$2.10/hr** |
| L5.1 Sentinel Foundation | +$0.31/hr *(free in trial)* | **$2.41/hr** |
| L5.2 Detection & Investigation | +$0.03/hr *(free in trial)* | **$2.44/hr** |
| L5.3 SOC Operations & Automation | +$0.01/hr | **$2.45/hr** |
| L6.1 High Availability & Redundancy | +$0.06/hr | **$2.16/hr** † |
| L6.2 Disaster Recovery Implementation | +$0.04/hr | **$2.20/hr** † |
| L6.3 Business Continuity & Validation | +$0.00/hr steady state | **$2.20/hr** † |

† Levels 5 and 6 are parallel tracks that both start from Level 4's $2.10/hr.
Level 6's running totals exclude Level 5. A class that runs **both**, with
Sentinel outside its free trial, reaches about **$2.55/hr**.

### Where the money actually goes

| Phase | Adds | Share of the $2.55/hr full stack |
|---|---|---|
| Level 1 · Deploy | $1.84/hr | **72%** |
| Level 2 · Monitor | $0.07/hr | 3% |
| Level 3 · Secure | $0.10/hr | 4% |
| Level 4 · Protect | $0.09/hr | 4% |
| Level 5 · Detect | $0.35/hr | 14% |
| Level 6 · Recover | $0.10/hr | 4% |

**Azure Firewall Standard alone is $1.25/hr — 49% of the full stack, and more
than Levels 2, 3, 4, 5 and 6 combined.** The five operational levels together
add $0.71/hr, which is less than the firewall. That single comparison is the
most useful cost slide in the curriculum, and it should appear in Level 1 rather
than at the end.

## Optimization levers, by size of effect

| Lever | Saving | Where it is taught |
|---|---|---|
| Tear down L1.2's firewall and web tier before Level 2 | −$1.41/hr | L1.2 |
| Azure Firewall Basic instead of Standard | −$0.855/hr | L1.2 |
| Run Level 5 inside the Sentinel free trial | −$0.34/hr for 31 days | L5.1 |
| Do not deploy Front Door Premium for WAF | avoids +$0.40/hr | L3.4 |
| Do not upgrade to Azure Firewall Premium | avoids +$0.50/hr | L3.4 |
| Keep SQL on Basic rather than a zone-redundant tier | avoids +$0.25/hr | L6.1 |
| Route verbose logs to Basic or Auxiliary tiers | −$0.03/hr at lab volume | L2.4 |
| Defender for Servers Plan 1 instead of Plan 2 | −$0.053/hr on 4 VMs | L3.2 |
| Protect one VM with Site Recovery, not four | −$0.10/hr | L6.2 |
| Scale the container app to zero minimum replicas | −$0.054/hr per region | L1.3 |
| LRS instead of GRS backup storage | −50% of backup storage | L4.1 |
| Enable Defender plans at resource scope, not subscription | avoids charging unrelated resources | L3.2 |
| Deallocate VMs overnight | −$0.0416/hr per VM (disks still bill) | L1.1 |
| 15-minute instead of 1-minute log alert evaluation | −$2.50/rule/month | L2.3 |
| Archive old recovery points instead of shortening retention | −90%+ of that storage | L4.4 |

## Keeping this page honest

The existing handouts in `unit cost/` are generated from a single rate table in
`Build-CostDocs.ps1`, so a price correction is a one-line change that
regenerates both documents. The lab-authoring phase should extend that same
table with the meters above rather than starting a second source of truth — the
script already computes incremental and cumulative totals from quantities, which
is exactly the shape this curriculum needs.

The wiki checker (`scripts/Publish-Wiki.ps1`) cross-checks the four existing
per-lab figures between `README.md` and `_Sidebar.md` so they cannot drift. When
these chapters become labs, the same check should cover them.

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Pricing data as a reviewable diff**
>
> **Why it matters:** these rates came from the Azure Retail Prices API, and they
> will be wrong eventually. Because they live in the repository rather than in a
> slide deck, updating them is a pull request — dated, attributed, and diffable
> against what the class was told last time.
> **Find it:** `unit cost/Build-CostDocs.ps1`, where every figure in both
> handouts derives from one `$Rates` array.
> **Beyond the lab:** any number you quote to a customer should have a commit
> behind it.
> [Docs →](https://docs.github.com/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/about-comparing-branches-in-pull-requests)

## Reference

- [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
- [Azure Monitor cost and usage](https://learn.microsoft.com/azure/azure-monitor/cost-usage)
- [Microsoft Sentinel pricing and billing](https://learn.microsoft.com/azure/sentinel/billing)
- [Microsoft Defender for Cloud pricing](https://azure.microsoft.com/pricing/details/defender-for-cloud/)
- [Azure Backup pricing](https://azure.microsoft.com/pricing/details/backup/)
- [Azure Site Recovery pricing](https://azure.microsoft.com/pricing/details/site-recovery/)
