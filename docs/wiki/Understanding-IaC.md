# Understanding IaC

> **Why read this?** This page is the "why" behind the workshop. Read it once and the labs stop feeling like magic — you will know what each tool is doing and why the pattern exists.

---

## 🧱 What "Infrastructure as Code" means

**Infrastructure as Code (IaC)** is the practice of describing your cloud resources — networks, virtual machines, databases — in **text files stored in version control**, instead of clicking through a portal. You hand those files to a tool, and the tool makes the cloud match what the files say.

The benefits over clicking:

| Benefit | What it means in practice |
|---------|--------------------------|
| **Repeatable** | Same file → same environment, every time, in any subscription |
| **Reviewable** | Changes are a diff in a pull request — not an untracked click nobody remembers |
| **Recoverable** | Deleted everything by accident? Re-run the file |
| **Auditable** | Git history shows who changed what infrastructure, and when |

### Declarative vs. imperative

Most IaC (including Bicep) is **declarative**: you describe the *desired end state* ("a VNet with these two subnets"), not a step-by-step procedure to get there. The engine works out the steps — and if the resource already exists in the right shape, it does nothing.

That "do nothing if already correct" property is called **idempotency**: running the same deployment twice is safe. It is why you can re-run any lab workflow without fear.

---

## 🔗 How the tools fit together

![Tools and workflow overview](diagram-understanding-iac-tools.svg)

| Tool | Its one job | Where you will see it |
|------|------------|----------------------|
| **VS Code** | The editor where everything happens | Every lab |
| **GitHub Copilot (agent mode)** | Reads the repo, writes/edits Bicep, runs `az bicep build` to check its own work. **You review its diffs.** | Every lab, Steps 1–2 |
| **Bicep** | The language you describe Azure resources in — compiles to ARM JSON | Every lab |
| **Azure Verified Modules (AVM)** | Pre-built, Microsoft-maintained Bicep building blocks (`br/public:avm/res/...`), version-pinned for reproducibility | Every `main.bicep` |
| **GitHub Actions** | Runs your deploy in the cloud on a button press. Lint → What-if → Deploy lives here. | Every lab, Step 3 |
| **OIDC federation** | Lets Actions log into Azure with a short-lived token instead of a stored password | [Deployment Guide](Deployment-Guide) |
| **Azure CLI (`az`) + Bicep CLI** | The commands that compile and deploy. Copilot runs these; so can you. | Everywhere |

---

## 🔁 The core loop: Lint → What-if → Deploy

Every deployment in this workshop follows the same three-step pattern. This is the most important habit IaC teaches:

![Lint to What-if to Deploy loop](diagram-understanding-iac-loop.svg)

1. **Lint** — `az bicep build` compiles the template and runs the linter. Catches typos and bad parameters *before* touching Azure.
2. **What-if** — `az deployment group what-if` shows a colour-coded preview: `+` create, `~` modify, `-` delete. **Read this every time** — it is how you catch an accidental delete before it happens.
3. **Deploy** — apply the change. Because Bicep is idempotent, only the differences are acted on.

> [!TIP]
> The What-if step is your safety net. Never skip it, even on a "simple" change — renaming a resource looks like a delete+create and *will* cause data loss if not caught here.

---

## 📖 Glossary — terms you will see throughout the labs

| Term | Plain meaning |
|------|--------------|
| **Resource group** | A folder for Azure resources. All labs in this workshop share **one resource group** per participant. |
| **Module** | A reusable chunk of Bicep. AVM modules are the pre-built, version-pinned ones. |
| **Parameter file** (`.bicepparam`) | The values (names, region, sizes) fed into a template — kept separate from the template logic so the same template can be used in multiple environments. |
| **Scope** | *Where* a deployment targets. These labs deploy at **resource group** scope (`az deployment group create`). |
| **What-if** | A dry run that reports planned changes without making them. |
| **Idempotent** | Running it again produces the same result — no duplicates, no errors. |
| **OIDC** | A way for GitHub Actions to prove its identity to Azure using a short-lived cryptographic token — no stored passwords. |
| **AVM** | Azure Verified Modules — Microsoft-maintained, tested, pinned Bicep modules. Use them instead of writing raw ARM resources. |

---

## 🔗 Where to learn more

- **Bicep fundamentals** (hands-on, free) — https://learn.microsoft.com/training/paths/fundamentals-bicep/
- **What is IaC?** — https://learn.microsoft.com/devops/deliver/what-is-infrastructure-as-code
- **Azure Verified Modules** — https://aka.ms/avm
- **Bicep + GitHub Actions** — https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-github-actions
- **The what-if operation** — https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if
- **Azure Well-Architected Framework** (why the labs are built the way they are) — https://learn.microsoft.com/azure/well-architected/

---

Ready? → [Start-Here Checklist](Start-Here-Checklist) → [L1 — Hub & Spoke](L1-Hub-and-Spoke)