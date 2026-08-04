<#
.SYNOPSIS
    Checks the wiki mirror in docs/wiki, and optionally publishes it.

.DESCRIPTION
    docs/wiki is the source of truth for the GitHub Wiki. This script is
    primarily a LINTER: it catches the things that silently break a wiki page
    -- links that 404, images that don't exist, a second H1 fighting the page
    title, a mermaid diagram with no text alternative, CRLF line endings that
    make every future diff unreadable -- and only then publishes.

    Publishing mirrors docs/wiki over the wiki repo INCLUDING DELETIONS, so a
    page deleted from docs/wiki disappears from the wiki. A plain file copy
    can never do that, which is how stale pages survive.

    Run it three ways:
      ./scripts/Publish-Wiki.ps1 -CheckOnly     # lint only, never touches the wiki (CI)
      ./scripts/Publish-Wiki.ps1 -WhatIf        # lint + show what would publish
      ./scripts/Publish-Wiki.ps1                # lint + publish

.PARAMETER CheckOnly
    Run the checks and exit. Never clones, never pushes. This is the mode CI
    uses on pull requests.

.PARAMETER Strict
    Promote every warning to an error. Content-standard checks (spotlights,
    mermaid text descriptions, callout style) start as warnings while the
    pages are being rewritten, and become fatal once the rewrite is done.

.PARAMETER Token
    A GitHub App installation access token, used as the HTTP password when
    pushing. Omit it to use whatever git credentials you already have.

.PARAMETER WikiPath
    Local wiki clone. Defaults to Demo-IaC_Demo_with_VSCode.wiki beside the
    repo root; it is gitignored, so keeping it there is safe.

.EXAMPLE
    ./scripts/Publish-Wiki.ps1 -CheckOnly
.EXAMPLE
    ./scripts/Publish-Wiki.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $CheckOnly,
    [switch] $Strict,
    [string] $Token,
    [string] $WikiPath,
    [string] $Message = 'Publish wiki from docs/wiki'
)

$ErrorActionPreference = 'Stop'

function Write-Ok($m)   { Write-Host "    [OK] $m"   -ForegroundColor Green }
function Write-Fail($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }
function Write-Warn($m) { Write-Host "    [WARN] $m" -ForegroundColor Yellow }
function Write-Info($m) { Write-Host "    [INFO] $m" -ForegroundColor DarkCyan }
function Write-Step($m) { Write-Host ""; Write-Host "  > $m" -ForegroundColor White }

$RepoRoot  = Split-Path $PSScriptRoot -Parent
$MirrorDir = Join-Path $RepoRoot 'docs/wiki'
if (-not $WikiPath) { $WikiPath = Join-Path $RepoRoot 'Demo-IaC_Demo_with_VSCode.wiki' }

$RepoUrl = 'https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode'
$WikiUrl = "$RepoUrl.wiki.git"

if (-not (Test-Path $MirrorDir)) { Write-Fail "No mirror at $MirrorDir"; exit 1 }

# Files that render on every page rather than being pages themselves.
$Chrome = @('_Sidebar.md', '_Footer.md')

$script:Errors   = 0
$script:Warnings = 0
function Add-Problem([string] $msg, [bool] $fatal) {
    # -Strict turns every content-standard warning into a build failure.
    if ($fatal -or $Strict) { Write-Fail $msg; $script:Errors++ }
    else                    { Write-Warn $msg; $script:Warnings++ }
}

# ---------------------------------------------------------------------------
# Markdown fences hide things that look like markup but aren't. A '# comment'
# in a bash block is not an H1, and 'curl -s' in a bash block is Linux curl,
# not the PowerShell alias. Every check below works on this classification.
# ---------------------------------------------------------------------------
function Get-Lines([string] $path) {
    $inFence = $false
    $lang    = ''
    $n       = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        $n++
        if ($line -match '^\s*```(.*)$') {
            if (-not $inFence) { $inFence = $true;  $lang = $Matches[1].Trim() }
            else               { $inFence = $false; $lang = '' }
            [pscustomobject]@{ N = $n; Text = $line; InFence = $true; Lang = $lang; IsFenceMarker = $true }
            continue
        }
        [pscustomobject]@{ N = $n; Text = $line; InFence = $inFence; Lang = $lang; IsFenceMarker = $false }
    }
}

Write-Host ""
Write-Host "  Wiki check -- $MirrorDir" -ForegroundColor White

$pages  = Get-ChildItem $MirrorDir -Filter *.md | Sort-Object Name
# Dotfiles (.gitattributes) are published config, not page assets.
$assets = Get-ChildItem $MirrorDir -File |
          Where-Object { $_.Extension -notin '.md' -and -not $_.Name.StartsWith('.') }

# ---- 1. Folder shape -------------------------------------------------------
Write-Step 'Folder shape'
$subdirs = Get-ChildItem $MirrorDir -Directory
if ($subdirs) {
    Add-Problem "docs/wiki must be flat -- found subdirectory: $($subdirs.Name -join ', ')" $true
} else { Write-Ok 'flat, no subdirectories' }

$allowed = '.md', '.png', '.svg', '.jpg', '.gif'
$stray = Get-ChildItem $MirrorDir -File |
    Where-Object { $_.Extension -notin $allowed -and $_.Name -ne '.gitattributes' }
if ($stray) {
    Add-Problem "unpublishable file(s) in the mirror: $($stray.Name -join ', ')" $true
} else { Write-Ok "$($pages.Count) pages, $($assets.Count) assets" }

# ---- 2. Line endings -------------------------------------------------------
# The wiki repo has autocrlf=true and no .gitattributes of its own. A CRLF
# file published from here shows every line as changed in the next diff.
Write-Step 'Line endings'
$crlf = @()
foreach ($p in $pages) {
    if ([System.IO.File]::ReadAllText($p.FullName) -match "`r`n") { $crlf += $p.Name }
}
if ($crlf) {
    Add-Problem "CRLF line endings (publish would rewrite the whole file): $($crlf -join ', ')" $true
} else { Write-Ok 'all pages are LF' }

# ---- 3. Exactly one H1 per page -------------------------------------------
Write-Step 'Headings'
foreach ($p in $pages) {
    $h1 = @(Get-Lines $p.FullName | Where-Object { -not $_.InFence -and $_.Text -match '^#\s' })
    $want = if ($p.Name -in $Chrome) { 0 } else { 1 }
    if ($h1.Count -ne $want) {
        $where = ($h1 | ForEach-Object { "line $($_.N)" }) -join ', '
        Add-Problem "$($p.Name): expected $want H1, found $($h1.Count) ($where)" $true
    }
}
if ($script:Errors -eq 0) { Write-Ok 'every page has exactly one H1 (code fences ignored)' }

# ---- 4. Links --------------------------------------------------------------
Write-Step 'Links'
$pageNames = $pages | ForEach-Object { $_.BaseName }
$assetNames = $assets | ForEach-Object { $_.Name }
$relCount = 0; $badWiki = 0; $badImg = 0

foreach ($p in $pages) {
    $text = [System.IO.File]::ReadAllText($p.FullName)

    # ../blob/main/... resolves from a live wiki URL but 404s from docs/wiki,
    # which defeats the point of reviewing the mirror in a pull request.
    foreach ($m in [regex]::Matches($text, '\]\((\.\./[^)]+)\)')) {
        Add-Problem "$($p.Name): relative link '$($m.Groups[1].Value)' -- use an absolute $RepoUrl/... URL" $true
        $relCount++
    }

    # Bare wiki links work on the wiki but not in the mirror. Allowed only in
    # _Sidebar/_Footer, which are never read as page bodies.
    foreach ($m in [regex]::Matches($text, '\]\(([A-Z][A-Za-z0-9-]*)\)')) {
        $target = $m.Groups[1].Value
        if ($target -notin $pageNames) {
            Add-Problem "$($p.Name): link to '$target' but $target.md does not exist" $true
            $badWiki++
        } elseif ($p.Name -notin $Chrome) {
            Add-Problem "$($p.Name): bare wiki link '$target' -- page bodies need the absolute $RepoUrl/wiki/... form" $false
        }
    }

    # Images are relative on purpose; that only works while the folder is flat.
    foreach ($m in [regex]::Matches($text, '(?:src="([^"]+)"|\]\(([^)\s]+\.(?:png|svg|jpg|gif))\))')) {
        $img = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        if ($img -match '^https?://') { continue }
        if ($img -notin $assetNames) {
            Add-Problem "$($p.Name): image '$img' not found in docs/wiki" $true
            $badImg++
        }
    }
}
if ($relCount -eq 0) { Write-Ok 'no relative ../ links' }
if ($badWiki -eq 0)  { Write-Ok 'every wiki link resolves to a real page' }
if ($badImg -eq 0)   { Write-Ok 'every image reference resolves' }

# ---- 5. Orphaned assets ----------------------------------------------------
$allText = ($pages | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
$orphans = $assetNames | Where-Object { $allText -notmatch [regex]::Escape($_) }
if ($orphans) { Add-Problem "asset(s) referenced by no page: $($orphans -join ', ')" $false }
else { Write-Ok 'no orphaned assets' }

# ---- 6. Mermaid needs a text alternative ----------------------------------
# Mermaid renders to a bare SVG with no alt text, so a <details> prose
# description is the accessibility equivalent of the alt attribute it replaced.
Write-Step 'Diagrams'
$mermaid = 0; $missingAlt = 0
foreach ($p in $pages) {
    $lines = @(Get-Lines $p.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not ($lines[$i].IsFenceMarker -and $lines[$i].Lang -eq 'mermaid')) { continue }
        $mermaid++
        # find the closing fence, then look at the next few non-blank lines
        $j = $i + 1
        while ($j -lt $lines.Count -and -not $lines[$j].IsFenceMarker) { $j++ }
        $tail = $lines[($j + 1)..([math]::Min($j + 4, $lines.Count - 1))] |
                Where-Object { $_.Text.Trim() -ne '' } | Select-Object -First 1
        if (-not $tail -or $tail.Text -notmatch '<details') {
            Add-Problem "$($p.Name) line $($lines[$i].N): mermaid diagram has no <details> text description" $false
            $missingAlt++
        }
    }
}
if ($mermaid -eq 0) { Write-Info 'no mermaid diagrams yet' }
elseif ($missingAlt -eq 0) { Write-Ok "$mermaid mermaid diagram(s), all with text descriptions" }

# ---- 7. Callout style ------------------------------------------------------
# Alert types carry meaning (NOTE/TIP/IMPORTANT/WARNING/CAUTION). An emoji
# blockquote is a hand-rolled substitute that renders inconsistently.
Write-Step 'Callouts'
$emojiQuotes = 0
foreach ($p in $pages) {
    foreach ($l in Get-Lines $p.FullName) {
        if ($l.InFence) { continue }
        if ($l.Text -match '^>\s+[\p{So}\p{Sk}]') {
            Add-Problem "$($p.Name) line $($l.N): emoji blockquote -- use a GitHub alert instead" $false
            $emojiQuotes++
        }
    }
}
if ($emojiQuotes -eq 0) { Write-Ok 'no emoji blockquotes' }

# ---- 8. GitHub feature spotlights -----------------------------------------
Write-Step 'GitHub feature spotlights'
$missingSpot = 0
foreach ($p in $pages) {
    if ($p.Name -in $Chrome) { continue }
    $n = ([regex]::Matches([System.IO.File]::ReadAllText($p.FullName), 'GitHub feature spotlight')).Count
    if ($n -lt 1 -or $n -gt 2) {
        Add-Problem "$($p.Name): $n spotlight(s), expected 1-2" $false
        $missingSpot++
    }
}
if ($missingSpot -eq 0) { Write-Ok 'every page has 1-2 spotlights' }

# ---- 9. curl in PowerShell fences -----------------------------------------
# In Windows PowerShell 5.1 'curl' is an alias for Invoke-WebRequest, which
# has no -s/-I. curl.exe is the real thing and ships with Windows 10+.
Write-Step 'Shell commands'
$bareCurl = 0
foreach ($p in $pages) {
    foreach ($l in Get-Lines $p.FullName) {
        if (-not $l.InFence -or $l.IsFenceMarker -or $l.Lang -ne 'powershell') { continue }
        if ($l.Text -match '(^|[\s|({])curl\s+-') {
            Add-Problem "$($p.Name) line $($l.N): bare 'curl -' in a powershell fence -- use curl.exe" $false
            $bareCurl++
        }
    }
}
if ($bareCurl -eq 0) { Write-Ok 'no bare curl in powershell fences' }

# ---- 10. Cost figures agree with the README -------------------------------
# The same four numbers appear in README.md, _Sidebar.md and the lab pages.
# Without this check they drift, and a stale price is worse than no price.
Write-Step 'Cost figures'
function Get-Costs([string] $path) {
    # Reads only table rows that name a lab, so prose figures elsewhere (the
    # "budget ~$2.00 for a demo hour" line) can't be mistaken for lab costs.
    # Formatting may differ between files -- README uses ~$1.65, the sidebar
    # ~$1.65/hr -- so only the number is compared.
    $map = [ordered]@{}
    foreach ($line in Get-Content $path) {
        if ($line -notmatch '^\s*\|') { continue }
        if ($line -match '\bL([1-4])\b' ) {
            $lab = "L$($Matches[1])"
            if ($line -match '~\$(\d+\.\d{2})') { $map[$lab] = $Matches[1] }
        }
    }
    $map
}

$readme  = Join-Path $RepoRoot 'README.md'
$sidebar = Join-Path $MirrorDir '_Sidebar.md'
if (-not (Test-Path $readme)) {
    Add-Problem 'README.md not found -- cannot cross-check cost figures' $false
} elseif (-not (Test-Path $sidebar)) {
    Add-Problem '_Sidebar.md not found -- cannot cross-check cost figures' $false
} else {
    $readmeCosts = Get-Costs $readme
    $sideCosts   = Get-Costs $sidebar
    if     ($readmeCosts.Count -eq 0) { Add-Problem 'README.md has no per-lab cost rows (| L1 … ~$0.24 |)' $false }
    elseif ($sideCosts.Count   -eq 0) { Add-Problem '_Sidebar.md has no per-lab cost rows' $false }
    else {
        $drift = @()
        foreach ($lab in @('L1','L2','L3','L4')) {
            $r = $readmeCosts[$lab]; $s = $sideCosts[$lab]
            if (-not $r -or -not $s) { $drift += "$lab missing (README=$r sidebar=$s)" }
            elseif ($r -ne $s)       { $drift += "$lab README=`$$r sidebar=`$$s" }
        }
        if ($drift) { Add-Problem "cost figures drifted -- $($drift -join '; ')" $false }
        else {
            $shown = @('L1','L2','L3','L4') | ForEach-Object { "$_=`$$($readmeCosts[$_])" }
            Write-Ok "per-lab costs agree across README and _Sidebar ($($shown -join ' '))"
        }
    }
}

# ---- Verdict ---------------------------------------------------------------
Write-Host ""
if ($script:Errors -gt 0) {
    Write-Fail "$($script:Errors) error(s), $($script:Warnings) warning(s) -- not publishing."
    exit 1
}
if ($script:Warnings -gt 0) {
    Write-Warn "$($script:Warnings) warning(s). These become errors under -Strict."
} else {
    Write-Ok 'all checks passed'
}

if ($CheckOnly) { Write-Host ""; Write-Info 'check-only; the wiki was not touched.'; Write-Host ""; exit 0 }

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------
Write-Step 'Sync the wiki clone'
if (-not (Test-Path (Join-Path $WikiPath '.git'))) {
    Write-Info "cloning $WikiUrl"
    git clone --quiet $WikiUrl $WikiPath
    if ($LASTEXITCODE -ne 0) { Write-Fail 'clone failed'; exit 1 }
}
git -C $WikiPath fetch --quiet origin
# The mirror is the source of truth, so never merge -- reset onto master.
git -C $WikiPath checkout --quiet -B master origin/master
if ($LASTEXITCODE -ne 0) { Write-Fail 'could not check out origin/master'; exit 1 }

# A 'main' branch here is a trap: GitHub only ever serves master, so a push to
# main looks successful and changes nothing.
if (git ls-remote --heads $WikiUrl main) {
    Write-Fail "the wiki has a 'main' branch. GitHub serves 'master' only -- delete it:"
    Write-Host "         git -C $WikiPath push origin --delete main" -ForegroundColor Yellow
    exit 1
}
Write-Ok 'wiki clone at origin/master'

Write-Step 'Mirror docs/wiki over the wiki (including deletions)'
# -WhatIf:$false is deliberate. The wiki clone is a scratch copy that was just
# reset to origin/master, so writing into it is free -- and it is the only way
# to compute the real diff to show. The push is what -WhatIf actually gates;
# letting -WhatIf skip these copies made the dry run report "nothing to
# publish" while changes were pending, which is the opposite of useful.
$mirrorFiles = Get-ChildItem $MirrorDir -File -Force
foreach ($f in $mirrorFiles) {
    Copy-Item $f.FullName (Join-Path $WikiPath $f.Name) -Force -WhatIf:$false
}
$keep = $mirrorFiles.Name
Get-ChildItem $WikiPath -File -Force | Where-Object { $_.Name -notin $keep } | ForEach-Object {
    Write-Info "removing $($_.Name) -- not in docs/wiki"
    Remove-Item $_.FullName -Force -WhatIf:$false
}

$pending = git -C $WikiPath status --porcelain
if (-not $pending) {
    Write-Ok 'the wiki already matches docs/wiki; nothing to publish.'
    Write-Host ""
    exit 0
}
Write-Host ""
git -C $WikiPath add -A
git -C $WikiPath --no-pager diff --cached --stat | ForEach-Object { Write-Host "    $_" }

if ($WhatIfPreference) {
    Write-Host ""
    Write-Warn 'DRY RUN -- nothing was pushed.'
    git -C $WikiPath reset --hard --quiet origin/master
    Write-Host ""
    exit 0
}

if ($PSCmdlet.ShouldProcess('the GitHub Wiki', 'publish docs/wiki')) {
    Write-Step 'Publish'
    git -C $WikiPath commit --quiet -m $Message
    # HEAD:master, never 'main main:master' -- a fresh clone has no local main,
    # so that refspec fails and aborts the whole push.
    if ($Token) {
        $authed = $WikiUrl -replace '^https://', "https://x-access-token:$Token@"
        git -C $WikiPath push --quiet $authed HEAD:master
    } else {
        git -C $WikiPath push --quiet origin HEAD:master
    }
    if ($LASTEXITCODE -ne 0) { Write-Fail 'push failed'; exit 1 }
    Write-Ok "published -- $(git -C $WikiPath rev-parse --short HEAD)"
    Write-Host "    $RepoUrl/wiki" -ForegroundColor Cyan
}
Write-Host ""
