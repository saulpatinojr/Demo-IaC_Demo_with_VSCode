# Curriculum Map 🗺️

Every chapter of the workshop on one page — and the one rule that makes it
navigable:

> [!IMPORTANT]
> **Go east first.** Run the **.1 chapter of each level, left to right:
> [L1.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-1-Core-Deployment) →
> [L2.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-1-Monitoring-Fundamentals) →
> [L3.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L3-1-Security-Foundation) →
> [L4.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L4-1-Backup-Fundamentals)**.
> That is the main path: deploy something, monitor it, check its security,
> back it up — every discipline at a similar, beginner-friendly complexity.
> There is no point admiring a full disaster-recovery estate before you can
> monitor a single VM.

**East (→)** moves to a *new discipline* at the same foundation depth.
**South (↓)** goes *deeper into the discipline you are in* — each step down
adds resources, cost, and prerequisites. South is optional; east never
requires it.

## The grid

Rows are depth (.1 = foundation … .4 = enterprise). Columns are the levels.
Every cell links to its chapter; **needs** tells you what must already be
deployed in your resource group before that chapter runs.

| ↓ Depth \ Level → | 1 · Deploy | 2 · Monitor | 3 · Secure | 4 · Protect | 5 · Detect ◇ | 6 · Recover ◇ |
|---|---|---|---|---|---|---|
| **.1 Foundation** ⭐ *the main path* | **[L1.1 Core Deployment](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-1-Core-Deployment)** 🟢 ~$0.24/hr · needs nothing | **[L2.1 Monitoring Fundamentals](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-1-Monitoring-Fundamentals)** 🟢 ~$0.06/hr · needs L1.1 | **[L3.1 Security Foundation](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L3-1-Security-Foundation)** 🟢 $0 · needs nothing | **[L4.1 Backup Fundamentals](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L4-1-Backup-Fundamentals)** 🟢 ~$10/mo · needs L1.1 | [L5.1 Sentinel Foundation](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L5-1-Sentinel-Foundation) 🟡 · needs L1.3 + Sentinel role | [L6.1 High Availability](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L6-1-High-Availability) 🟢 $0 · needs nothing |
| **.2** | [L1.2 Architecture Expansion](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-2-Architecture-Expansion) 🔴 ~$1.65/hr running — its firewall alone is $1.25/hr · needs L1.1 | [L2.2 Operational Visibility](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-2-Operational-Visibility) 🟢 ~$0.02/hr · needs L1.3 (+L1.4 for the web test) | [L3.2 Workload Protection](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L3-2-Workload-Protection) 🟡 ~$15/mo per SQL server · needs L1.3 | [L4.2 PaaS Protection](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L4-2-PaaS-Protection) 🟢 ~$0.01/hr · needs L1.3 | [L5.2 Detection & Investigation](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L5-2-Detection-Investigation) 🟡 · needs L5.1 | [L6.2 Disaster Recovery](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L6-2-Disaster-Recovery) 🟡 · needs L4.1 |
| **.3** | [L1.3 Multi-Service Application](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-3-Multi-Service-Application) 🟠 ~$1.73/hr running · needs L1.1 (**not** L1.2) | [L2.3 Proactive Operations](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-3-Proactive-Operations) 🟢 ~$2.30/mo · needs L1.1 + L1.3 | [L3.3 Security Operations](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L3-3-Security-Operations) 🟢 ~$0.03/hr · needs L1.3 | [L4.3 Backup Operations](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L4-3-Backup-Operations) 🟢 ~$0.01/hr · needs L4.1 + L1.3 + L2.3 | [L5.3 SOC Operations](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L5-3-SOC-Operations) 🟡 · needs L5.2 | [L6.3 Continuity Validation](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L6-3-Continuity-Validation) 🟢 · needs L1.3 + L2.3 |
| **.4** | [L1.4 Production Platform](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-4-Production-Platform) 🔴 ~$1.84/hr running (Front Door + 2nd SQL) · needs L1.3 | [L2.4 Monitoring Strategy](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-4-Monitoring-Strategy) 🟢 *saves* money · needs L1.3 + L2.3 | [L3.4 Security Architecture](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L3-4-Security-Architecture) 🟢 $0 · needs nothing | [L4.4 Data Protection Strategy](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L4-4-Data-Protection-Strategy) 🟢 ~$0.01/hr · needs L4.1 | — | — |

⭐ = the main path · ◇ = extra-credit levels (L5 needs an extra Azure role;
L5 and L6 are parallel tracks — either order, or skip) · 🟢🟡🟠🔴 = cost/weight
at a glance. All 22 chapters deploy into the **same resource group** you were
assigned; costs bill only while resources stay deployed.

## Why east stays easy

Each .1 chapter is the *foundation* of its discipline, sized like L1.1:

| Main path stop | What you do | What it needs | Cost |
|---|---|---|---|
| [L1.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L1-1-Core-Deployment) | Deploy the core: hub + spoke VNets, Bastion, one VM | your empty resource group | ~$0.24/hr |
| [L2.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L2-1-Monitoring-Fundamentals) | Put an agent + data collection rule on that VM, wire diagnostics into Log Analytics | L1.1 | ~$0.06/hr |
| [L3.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L3-1-Security-Foundation) | Deploy a security-posture workbook over everything you have built | nothing | $0 |
| [L4.1](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-L4-1-Backup-Fundamentals) | Create a Recovery Services vault and protect your VM with daily backups | L1.1 | ~$10/mo |

Every deploy workflow already defaults to this path — run them in order with
the defaults and each one succeeds on top of the last.

## Why south gets harder

Going down a column, chapters assume more of the estate exists:

- **L1.3 is the real gatekeeper.** Its workspace, SQL database, Key Vault and
  container app are what most .2/.3/.4 chapters in Levels 2–6 attach to. If a
  southern chapter's **needs** lists L1.3, deploy L1.3 first.
- **L1.2 is a pure cost detour.** Nothing anywhere requires it — it exists to
  teach hub-firewall architecture. Its Azure Firewall is **$1.25/hr**, more
  than everything else in Level 1 combined. Deploy it deliberately, tear it
  down promptly. Chapters that *can* use it (L2.1, L2.3, L4.1) have an
  `include_web_tier` switch that is **off by default** — turn it on only while
  L1.2 is standing.
- **L1.4's second region** is only consumed by three switchable features
  (L2.2's web test, L3.2's and L4.2's secondary coverage) — all off by default.
- **L4.1 freezes two choices forever** (vault redundancy, cross-region
  restore) the moment the first VM is protected — read its page before the
  first run.

## Level overviews

Prefer prose to grids? Each level has an overview page that walks its column:
[Level 1 · Deploy](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-1-Deploy) ·
[Level 2 · Monitor](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-2-Monitor) ·
[Level 3 · Secure](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-3-Secure) ·
[Level 4 · Protect](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-4-Protect) ·
[Level 5 · Detect](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-5-Detect) ·
[Level 6 · Recover](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Level-6-Recover)

For the design history behind the six levels, see
[Curriculum Redesign](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Redesign);
for the money view, [Curriculum Cost Model](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Curriculum-Cost-Model).

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Workflow inputs**
>
> **You just used it:** the "needs" notes above map to checkboxes. Every deploy workflow in this repo exposes its assumptions — `include_web_tier`, `include_app_tier`, `secondary_region` — as `workflow_dispatch` inputs that default to the main path, so the Run workflow form *is* the dependency contract.
> **Find it:** any workflow file under `.github/workflows/`, in the `on: workflow_dispatch: inputs:` block.
> **Beyond the lab:** inputs turn one workflow into a family of runs — parameterize environment, region or dry-run instead of cloning YAML.
> [Docs →](https://docs.github.com/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch)
