# Wiki draft — dual deploy path (Bicep primary + Copilot alternative)

Staging area for the redesigned lab pages. GitHub wikis can't be branched or
reviewed via PR (GitHub serves only the wiki's `master`), so the proposed pages
live here on the feature branch to keep the whole change reviewable in one PR.

## What changed vs. the live wiki

Each lab page (L1–L4) now leads with the **Bicep deploy** as the primary path,
run through the **GitHub Actions workflow**. Credentials are stored **once** by
the existing `Setup-Oidc.ps1` one-shot (OIDC + `gh secret set`), so there is
**nothing to paste per lab** — Actions signs in with OIDC and reads the stored
secrets/variables. Each page shows an optional `gh secret list` / `gh variable
list` confirmation and a `gh workflow run deploy-lN.yml` shortcut.

The **GitHub Copilot** path is a clearly badged callout (logo + prompt +
benefits) placed **after the Test steps and before "What carries forward"**. Its
prompts drive the same workflow — edit the Bicep, `az bicep build`, commit, push,
then `gh workflow run` — so Copilot never handles credentials either.

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
