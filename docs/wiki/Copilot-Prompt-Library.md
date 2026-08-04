# Copilot Prompt Library

Copy-paste prompts that work against this repo, grouped by what you want to do. Dip in as needed — this is a reference page, not a tutorial.

| Who this is for | Time | You need first |
|---|---|---|
| Anyone using Option 3 in a lab | Dip in as needed | Copilot Chat in **agent mode**, and `./scripts/Load-LabSettings.ps1` run once |

> [!IMPORTANT]
> These are written for **agent mode**, not ask mode. Press `Ctrl+Alt+I`, then switch the dropdown from *Ask* to *Agent*. Ask mode can only talk about your code; agent mode can read files, edit them, run `az bicep build`, and run the deploy. Every prompt below assumes it can act.

> [!TIP]
> This repo ships a [`.github/copilot-instructions.md`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/.github/copilot-instructions.md), which Copilot reads automatically. It already knows to use Azure Verified Modules, pin versions, keep the prefix under 12 characters and deploy at resource-group scope — so you don't have to say any of that.

---

## Deploy as-is

Swap the path for whichever lab you are on.

> Deploy `labs/L1-hub-spoke/main.bicep` to my lab resource group (`$env:AZURE_RESOURCE_GROUP`) using `labs/L1-hub-spoke/main.bicepparam`. Run `az bicep build` first, then `what-if`, then `create`.

**What it should do:** compile, show you the what-if diff, and wait. **If it errors:** paste the error back verbatim — that is the loop, and it is usually one round.

---

## Modify, then deploy

The exercise built into each lab page:

| Lab | Prompt |
|---|---|
| **L1** | > Add a `snet-data` subnet `10.1.2.0/24` to the spoke VNet in `labs/L1-hub-spoke/main.bicep`, run `az bicep build` to check it, then deploy. |
| **L2** | > Limit the firewall's outbound rule in `labs/L2-web-tier/main.bicep` to port 443 only — remove 80 — run `az bicep build`, then deploy. |
| **L3** | > In `labs/L3-containers/main.bicep`, raise `maxReplicas` to 5 and add an env var `GREETING=Hello L3` to the container, run `az bicep build`, then deploy. |
| **L4** | > Switch the Front Door origin group in `labs/L4-global/main.bicep` to weighted round-robin across both regions instead of priority failover, run `az bicep build`, then deploy. |

---

## Understand what is already there

Reading is where agent mode is most under-used.

> Explain `labs/L2-web-tier/main.bicep` to me as if I know Azure but not Bicep. Focus on how inbound traffic reaches a web VM, and why the load balancer is internal rather than public.

> Trace every resource in `labs/L3-containers/main.bicep` that has `publicNetworkAccess` set to `Disabled`, and tell me exactly how the container app still reaches each one.

> Compare `labs/L1-hub-spoke/main.bicep` and `labs/L3-containers/main.bicep`. Which VNet does each one create, and which of them peer to what?

---

## Diagnose a failure

> This deployment failed with the error below. Read the relevant template in `labs/`, tell me the specific cause, and propose the smallest fix. Do not change anything yet.
>
> ```
> <paste the full error, including the correlation ID>
> ```

> Run `az deployment group list -g $env:AZURE_RESOURCE_GROUP --query "[?properties.provisioningState=='Failed']"`, pick the most recent failure, and show me which operation inside it failed and why.

---

## Harden it

> Review `labs/L2-web-tier/main.bicep` against the Azure Well-Architected Framework's Security pillar. List what it does well and what it does not, ranked by risk. Do not change anything — just the review.

> The NSG in `labs/L2-web-tier/main.bicep` allows inbound 80 from `10.0.0.0/8`. Narrow it to only the firewall subnet, explain why that is safe, run `az bicep build`, then show me the `what-if`.

---

## Build what the labs deliberately left out

This is the most realistic exercise in the workshop, because you are fixing a design rather than following steps.

> In `labs/L4-global/main.bicep`, the DR server `sql-<prefix>-<suffix>-dr` sets `publicNetworkAccess: 'Disabled'` but has no private endpoint, and the secondary Container Apps environment has no VNet integration — so after a failover nothing can reach the promoted database. Add a VNet in `westus2` with a private-endpoint subnet, a private DNS zone linked to it, and a private endpoint on the DR server. Use Azure Verified Modules and keep versions pinned. Run `az bicep build`, then `what-if`. Do not deploy.

See the [Well-Architected scorecard](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/L4-Global-Scale) on the L4 page for why this gap matters.

---

## Writing your own prompts

Four things separate a prompt that works from one that wanders:

1. **Name the file.** `labs/L2-web-tier/main.bicep`, not "the firewall template". Agent mode will find it either way, but naming it stops the guessing.
2. **Say where to stop.** "Run `what-if`, do not deploy" is a different task from "deploy". Be explicit, especially when it costs money.
3. **Ask for the check.** Adding "run `az bicep build`" makes Copilot verify its own work before handing it back, and it fixes most of its own mistakes that way.
4. **Paste errors whole.** Truncating an Azure error usually removes the part that identifies the cause.

> [!WARNING]
> **You are the reviewer.** Read every diff before accepting it, and read every `what-if` before deploying. Agent mode is fast and confident, and confidently wrong occasionally — the `what-if` step exists precisely so a bad edit costs you nothing.

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Repository instructions for Copilot**
>
> **You just used it:** none of the prompts above mention Azure Verified Modules, version pinning, the 12-character prefix limit or resource-group scope — because Copilot already knows. The repo tells it.
> **Find it:** [`.github/copilot-instructions.md`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/.github/copilot-instructions.md). Copilot reads it automatically on every request in this repo; you never attach it.
> **Beyond the lab:** house conventions live with the code instead of in someone's head, so every contributor — human or AI — starts from the same rules. It is a plain markdown file, and reviewing changes to it is a normal pull request.
> [Docs →](https://docs.github.com/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
