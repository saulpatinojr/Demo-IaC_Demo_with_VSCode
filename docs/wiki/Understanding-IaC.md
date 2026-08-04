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

```mermaid
flowchart LR
  subgraph LOCAL["Your machine · VS Code"]
    COP["GitHub Copilot<br/>agent mode"]
    BICEP["Bicep files<br/>.bicep + .bicepparam"]
  end

  AVM["Azure Verified Modules<br/>Microsoft's published building blocks"]
  REPO["GitHub repository"]
  GHA["GitHub Actions<br/>workflow"]
  AZ["Azure"]

  COP -->|"writes and edits"| BICEP
  BICEP -->|"references, version-pinned"| AVM
  BICEP -->|"az bicep build, what-if, deploy"| AZ
  BICEP -->|"git push"| REPO
  REPO -->|"triggers"| GHA
  GHA -->|"OIDC login, no password"| AZ

  classDef compute fill:#eefaf0,stroke:#3a9d5d,color:#1a1a1a
  classDef net fill:#eef4ff,stroke:#4472c4,color:#1a1a1a
  classDef data fill:#f5eefc,stroke:#7c4dbe,color:#1a1a1a
  class COP,BICEP compute
  class REPO,GHA net
  class AVM,AZ data
```

<details><summary>Text description of this diagram</summary>

You write Bicep in VS Code, with Copilot agent mode doing much of the typing.
The templates reference **Azure Verified Modules** — building blocks Microsoft
publishes and versions, so you describe *what* you want rather than wiring every
resource by hand.

From there the same template reaches Azure two ways. Locally you run
`az bicep build`, `what-if` and `deploy` yourself. Or you push to GitHub, where
a workflow does the same three steps and signs in with OIDC — no password
anywhere.

That is the point of the three deploy options in every lab: one template, three
routes to the same result.

</details>

| Tool | Its one job | Where you will see it |
|------|------------|----------------------|
| **VS Code** | The editor where everything happens | Every lab |
| **GitHub Copilot (agent mode)** | Reads the repo, writes/edits Bicep, runs `az bicep build` to check its own work. **You review its diffs.** | Every lab, Steps 1–2 |
| **Bicep** | The language you describe Azure resources in — compiles to ARM JSON | Every lab |
| **Azure Verified Modules (AVM)** | Pre-built, Microsoft-maintained Bicep building blocks (`br/public:avm/res/...`), version-pinned for reproducibility | Every `main.bicep` |
| **GitHub Actions** | Runs your deploy in the cloud on a button press. Lint → What-if → Deploy lives here. | Every lab, Step 3 |
| **OIDC federation** | Lets Actions log into Azure with a short-lived token instead of a stored password | [Deployment Guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Deployment-Guide) |
| **Azure CLI (`az`) + Bicep CLI** | The commands that compile and deploy. Copilot runs these; so can you. | Everywhere |

---

## 🔁 The core loop: Lint → What-if → Deploy

Every deployment in this workshop follows the same three-step pattern. This is the most important habit IaC teaches:

```mermaid
flowchart LR
  EDIT["Edit the Bicep"]
  LINT["1 · Lint<br/>az bicep build<br/>does it compile?"]
  WHATIF["2 · What-if<br/>az deployment group what-if<br/>what would change?"]
  CHECK{"Does the diff<br/>match what you meant?"}
  DEPLOY["3 · Deploy<br/>az deployment group create"]

  EDIT --> LINT --> WHATIF --> CHECK
  CHECK -->|"yes"| DEPLOY
  CHECK -->|"no"| EDIT

  classDef step fill:#eef4ff,stroke:#4472c4,color:#1a1a1a
  classDef go fill:#eefaf0,stroke:#3a9d5d,color:#1a1a1a
  classDef ask fill:#fff9e6,stroke:#c9a227,color:#1a1a1a
  class EDIT,LINT,WHATIF step
  class DEPLOY go
  class CHECK ask
```

<details><summary>Text description of this diagram</summary>

Every change follows the same three steps, and the loop is the habit worth
building.

**Lint** (`az bicep build`) answers "does this compile?" — it catches typos and
bad parameters in seconds, before anything touches Azure. **What-if** answers
the more important question: "what would this actually change?" It lists every
resource that would be created, modified or **deleted**, without doing any of it.

Then you read that diff. If it doesn't match what you intended, go back and
edit — you have lost nothing, because nothing has happened yet. Only when the
diff looks right do you **deploy**.

The GitHub Actions workflows run these same three steps in the same order, so
the button and the terminal behave identically.

</details>

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

Ready? → [Start-Here Checklist](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist) → [L1 — Hub & Spoke](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/L1-Hub-and-Spoke)