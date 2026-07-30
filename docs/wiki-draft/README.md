# Wiki draft — dual deploy path (Bicep primary + Copilot alternative)

Staging area for the redesigned lab pages. GitHub wikis can't be branched or
reviewed via PR (GitHub serves only the wiki's `master`), so the proposed pages
live here on the feature branch to keep the whole change reviewable in one PR.

## What changed vs. the live wiki

Each lab page (L1–L4) now leads with a **local `az` deploy** as the primary path:
a **one-time** block (in L1) saves prefix, location, and the VM/SQL passwords to
persistent user environment variables, so every later lab is just
`what-if` + `create` with **nothing pasted per lab**. The `.bicepparam` files
read those env vars.

Two **alternative callouts** follow the same primary/alternative pattern:
- **⚙️ GitHub Actions** — right after the deploy steps: run the one-time
  `Setup-Oidc.ps1`, then trigger the workflow (`gh workflow run deploy-lN.yml`).
  Logs in with OIDC, nothing local needed.
- **Copilot** — badged callout (logo) placed after Test and before "What carries
  forward"; its prompts edit the Bicep and run the local `az deployment` for you.

## Files

| Draft file | Publishes to wiki page |
|---|---|
| `L1-Hub-and-Spoke.md` | `L1-Hub-and-Spoke.md` |
| `L2-Web-Tier-and-Firewall.md` | `L2-Web-Tier-and-Firewall.md` |
| `L3-Containers-and-Data.md` | `L3-Containers-and-Data.md` |
| `L4-Global-Scale.md` | `L4-Global-Scale.md` |
| `copilot-logo.png` | `copilot-logo.png` (referenced by each page) |

## Publish (after this PR is approved)

From the repo root, copy the approved drafts into the wiki working copy and push
to the wiki's `master` (the branch GitHub actually serves):

```powershell
$wiki = "Demo-IaC_Demo_with_VSCode.wiki"
Copy-Item docs/wiki-draft/*.md   $wiki/ -Force
Copy-Item docs/wiki-draft/*.png  $wiki/ -Force
Push-Location $wiki
git add -A
git commit -m "Publish dual-path lab pages (Bicep primary + Copilot alternative)"
git push origin main main:master
Pop-Location
```
