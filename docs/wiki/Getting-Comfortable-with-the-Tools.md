# Getting Comfortable with the Tools

> **Before you start:** this page is a 15-minute hands-on warm-up. Nothing here deploys anything to Azure. Work through it in order in your clone of the repo — by the end every tool will feel familiar.

---

## 1. 🧑‍💻 VS Code — 5 minutes

The editor is your home base for the whole workshop.

| Action | How |
|--------|-----|
| Open the repo | `File → Open Folder` → pick your clone |
| Command Palette | `Ctrl+Shift+P` — search for anything |
| Integrated terminal | `` Ctrl+` `` (backtick) |
| Source control (stage/commit/push) | Branch icon in the left rail, or `Ctrl+Shift+G` |
| Accept recommended extensions | Pop-up on first open, or Extensions view → **Recommended** |

**Try it:** open the terminal (`` Ctrl+` ``), run `az bicep version`, then open `labs/L1-hub-spoke/main.bicep` and hover over `br/public:avm/res/network/virtual-network:0.9.0`. The Bicep extension shows the module's parameters inline.

Docs: https://code.visualstudio.com/docs

---

## 2. 🧱 Bicep — 5 minutes

Bicep is the language you use to describe Azure infrastructure. You do not need to write much from scratch — Copilot and AVM do the heavy lifting — but you need to be able to *read* it.

A minimal Bicep file:

```bicep
// A parameter (an input) with a default value
param location string = 'eastus2'

// A module: reuse a pre-built Azure Verified Module, version-pinned
module vnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: 'my-vnet'
  params: {
    name:            'vnet-demo'
    location:        location
    addressPrefixes: ['10.0.0.0/16']
  }
}

// An output (a value readable after deploy — e.g. the URL or resource ID)
output vnetId string = vnet.outputs.resourceId
```

Three things to recognise:

- **`param`** — inputs, usually supplied by the `.bicepparam` file alongside the template.
- **`module 'br/public:avm/...'`** — an [Azure Verified Module](https://aka.ms/avm). The `:0.9.0` is a **pinned version** — the same version produces the same result every deploy.
- **`output`** — values surfaced after deploy (the workflows print these: app URL, firewall IP, etc.).

**Try it — compile without deploying:**

```powershell
az bicep build --file labs/L1-hub-spoke/main.bicep --stdout | Select-Object -First 20
```

If it prints JSON, it compiled. That ARM JSON is what Azure actually receives — you write Bicep, Azure gets JSON.

Docs: https://learn.microsoft.com/azure/azure-resource-manager/bicep/ · Learn path: https://learn.microsoft.com/training/paths/fundamentals-bicep/

---

## 3. 🤖 GitHub Copilot — agent mode — 5 minutes

Copilot **agent mode** is the star of the workshop. Unlike plain autocomplete, agent mode reads across multiple files, edits several at once, and runs terminal commands (like `az bicep build`) — pausing for your approval before each action.

**Set up:**

1. Press `Ctrl+Alt+I` to open Copilot Chat.
2. Change the mode dropdown (top of the chat panel) from **Ask** to **Agent**.
3. Confirm you are signed in (bottom-left account icon in VS Code).

**How to write good prompts:**

- **Name the file:** *"In `labs/L1-hub-spoke/main.bicep`, add a subnet…"* — pointing at a specific file focuses Copilot.
- **Ask it to verify itself:** *"…then run `az bicep build` on the file and fix any errors."*
- **Review every diff.** Agent mode proposes changes; you decide. Accept, tweak, or reject. Never merge without reading.

**Try it (safe — fully reversible):**

> In `labs/L1-hub-spoke/main.bicep`, add a second subnet named `snet-data` with address prefix `10.1.2.0/24` to the spoke VNet, then run `az bicep build` to verify it compiles.

Read the diff it proposes. Then discard it — Source Control → discard changes. L1 works fine without this change.

> [!TIP]
> **Copilot etiquette for IaC:** if it suggests raw ARM resources or old API versions, say: *"Use the pinned AVM module versions already present in this repo."* Consistency matters.

Docs: https://code.visualstudio.com/docs/copilot/chat/chat-agent-mode

---

## You are warmed up

You can open the repo, read Bicep, compile a template, and drive Copilot. That is everything the labs assume.

→ Head to the [Start-Here Checklist](Start-Here-Checklist) to finish setup, then [L1 — Hub & Spoke](L1-Hub-and-Spoke).

For install links and deeper CLI reference, see [Tools and References](Tools-and-References).