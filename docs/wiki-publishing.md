# Publishing the wiki

`docs/wiki/` is a **1:1 mirror of the GitHub Wiki**, kept in this repo so wiki
changes get the same review as code. GitHub wikis can't be branched or reviewed
via PR — GitHub serves one branch (`master`) and browser edits land straight on
it — so the mirror is the only place a wiki change can be diffed before readers
see it.

**The mirror is the source of truth.** Publishing copies this folder over the
wiki, including deletions. Never edit the wiki in the browser: the next publish
overwrites it and the change is lost with no trace.

## Rules for this folder

It is **flat and pure**. Every file in it becomes a wiki page or a wiki asset,
and nothing else belongs there:

- A `.md` file becomes a page named after the file (`Home.md` → `Home`). That is
  why this document lives at `docs/wiki-publishing.md` and *not* inside
  `docs/wiki/` — it would otherwise publish itself as a stray page.
- No subdirectories. Images are referenced relatively (`src="bicep.png"`), which
  resolves in both the wiki and this repo's file view only while the folder is flat.
- `_Sidebar.md` and `_Footer.md` are GitHub wiki conventions — they render on every
  page. `_Sidebar.md` **replaces** the auto-generated page list, so any page it
  doesn't link becomes reachable only by search.

## Icons

Two tiers, and the distinction is deliberate.

**Vendor logos** — `bicep.png`, `gh-actions.png`, `gh-copilot.png`. Used *only* in
the lab deploy chooser, because that is the one place the reader picks between
real products. Full colour, and never redrawn or recoloured.

**Supporting icons** — `icon-*.svg`, taken from
[Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons)
(Microsoft's own set, MIT licensed, so redistribution here is clean). These mark
ways of working rather than products, so they are monochrome line icons and stay
visually subordinate to the vendor logos.

| File | Fluent icon | Used for |
|---|---|---|
| `icon-spotlight.svg` | Lightbulb | the GitHub feature spotlight callout |
| `icon-one-command.svg` | Flash | Deployment Guide — one-command setup |
| `icon-step-by-step.svg` | Text Bullet List | Deployment Guide — manual steps |
| `icon-instructor.svg` | Hat Graduation | Start Here — instructor provisioned |
| `icon-self-service.svg` | Person | Start Here — self-service |
| `icon-windows.svg` | Desktop | Getting Comfortable — Windows |
| `icon-macos-linux.svg` | Laptop | Getting Comfortable — macOS / Linux |
| `icon-new-here.svg` | Book Open | Home — new to all of this |
| `icon-know-azure.svg` | Cloud | Home — knows Azure, new to GitHub |
| `icon-just-deploy.svg` | Rocket | Home — straight to the first lab |

Fetched from `assets/<Name>/SVG/ic_fluent_<name>_24_regular.svg` at 24 px regular
weight. The only modification is the fill: Fluent ships `#212121`, which
disappears on a dark background. All ten are recoloured to `#6e7781`, which
clears 4.5:1 contrast on both white and GitHub's dark `#0d1117`. An `<img src>`
cannot inherit `currentColor`, so a fixed mid-tone is the only option that works
in both themes.

**No OS brand marks.** The Windows flag and Apple logo are trademarks with their
own usage terms, not MIT — hence neutral Desktop/Laptop icons, with the label
doing the naming.

## Link policy

The wiki and this folder are read at different URLs, so only absolute links work
in both. The old `](../blob/main/…)` form resolves from a live wiki page but 404s
from `docs/wiki/`, which defeats the point of reviewing the mirror.

| Link target | Use |
|---|---|
| A file in this repo | absolute — `https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/labs/…` |
| Another wiki page, from a page body | absolute — `https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/L2-Web-Tier-and-Firewall` |
| Another wiki page, from `_Sidebar.md` / `_Footer.md` | relative — `L2-Web-Tier-and-Firewall` |
| An image | relative — `bicep.png` |

Absolute links hardcode `saulpatinojr`. That is deliberate: the wiki is only ever
published to the canonical repo, and forks send readers to the canonical wiki.

## Publishing

```powershell
git -C Demo-IaC_Demo_with_VSCode.wiki fetch origin
git -C Demo-IaC_Demo_with_VSCode.wiki reset --hard origin/master
robocopy docs\wiki Demo-IaC_Demo_with_VSCode.wiki /MIR /XD .git
git -C Demo-IaC_Demo_with_VSCode.wiki add -A
git -C Demo-IaC_Demo_with_VSCode.wiki commit -m "Publish wiki from docs/wiki"
git -C Demo-IaC_Demo_with_VSCode.wiki push origin HEAD:master
```

Two things that were previously wrong here and fail silently if reintroduced:

- **`HEAD:master`, not `main main:master`.** A fresh wiki clone has no local `main`,
  so that refspec fails with `src refspec main does not match any` and aborts the
  entire push — nothing publishes.
- **`/MIR`, not `Copy-Item *.md`.** A copy can add and overwrite but never delete,
  so a page removed from `docs/wiki/` would live on in the wiki forever.

The wiki clone is gitignored, so keeping it at the repo root is safe.

## Mirror provenance

Mirrored from wiki `master` at `db6a922` on 2026-08-04. At that point the wiki also
had a `main` branch, 15 commits behind `master` and 0 ahead. GitHub only ever serves
`master`, so `main` had no purpose and was actively dangerous — a push to it looks
successful and changes nothing.

Every file was verified byte-identical to the live wiki **except** the two below,
where the repo copy was deliberately kept:

| Page | Why it differs from live |
|---|---|
| `L1-Hub-and-Spoke.md` | Carries the correction that the test VM has **no** internet egress. Default outbound access was retired 30 Sep 2025, so the live page's "outbound works" test could never pass. |
| `L2-Web-Tier-and-Firewall.md` | Documents routing L1's `snet-workload` through the firewall, and an IP-flow test that looks up the VM's real address instead of a hardcoded one. |

Going the other way, the **live** pages were ahead on a point the repo drafts had
lost: all four labs use `## Deploy …` (H2), while the drafts had regressed it to a
second `#` competing with the page title. Live's `##` was restored on L1 and L2, and
L3/L4 were taken from live wholesale.

That reconciliation is why this mirror was hand-diffed rather than copied. Once
publishing runs from `docs/wiki/`, the two copies cannot drift again.
