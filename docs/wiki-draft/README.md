# Wiki draft — dual deploy path (Bicep primary + Copilot alternative)

Staging area for the redesigned lab pages. GitHub wikis can't be branched or
reviewed via PR (GitHub serves only the wiki's `master`), so the proposed pages
live here on the feature branch to keep the whole change reviewable in one PR.

## What changed vs. the live wiki

Each lab page (L1–L4) presents **three clearly separated deploy options** with a
chooser table (icons) up top, then one divided section each, in fixed order:

1. **Bicep CLI** — local `az` deploy; a one-time block (L1) persists values so
   later labs are just `what-if` + `create`.
2. **GitHub Actions** — push-button via OIDC (`Setup-Oidc.ps1` one-shot).
3. **GitHub Copilot** — plain-English agent prompt that edits + deploys.

Each option has its own icon (`docs/art/*.png`), a `---` divider, and a
plain-language "best if…" line so technical and non-technical readers can both
find their lane and copy-paste along.

## Files

| Draft file | Publishes to wiki page |
|---|---|
| `L1-Hub-and-Spoke.md` | `L1-Hub-and-Spoke.md` |
| `L2-Web-Tier-and-Firewall.md` | `L2-Web-Tier-and-Firewall.md` |
| `L3-Containers-and-Data.md` | `L3-Containers-and-Data.md` |
| `L4-Global-Scale.md` | `L4-Global-Scale.md` |
| `bicep.png`, `gh-actions.png`, `gh-copilot.png` | same names (referenced by each page) |

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
