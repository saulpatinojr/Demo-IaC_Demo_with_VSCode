<#
.SYNOPSIS
    Connects lab prerequisites: validates auth and forks the workshop repo to your account.

.DESCRIPTION
    This script uses your signed-in GitHub and Azure CLI sessions to:
      1) Validate GitHub CLI authentication
      2) Validate Azure CLI authentication
      3) Fork the workshop repo to your GitHub account (if not already forked)
      4) Install/verify the GitHub Copilot CLI extension

    After this script completes, use the fork URL printed at the end to clone the
    repo in the next step (Section F in the checklist).

    It is safe to re-run (idempotent): existing fork and Copilot CLI are detected
    and reused.

.PARAMETER UpstreamRepo
    Source repo to fork (owner/name). Defaults to the workshop repo.

.EXAMPLE
    ./Connect-AzureAndGitHub.ps1

.EXAMPLE
    ./scripts/Connect-AzureAndGitHub.ps1
#>
[CmdletBinding()]
param(
    [string] $UpstreamRepo = 'saulpatinojr/Demo-IaC_Demo_with_VSCode'
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n  > $msg" -ForegroundColor White }
function Write-Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "    [INFO] $msg" -ForegroundColor DarkCyan }
function Write-Warn($msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "    [FAIL] $msg" -ForegroundColor Red }

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Fail "Required command '$Name' was not found on PATH."
        throw "Missing command: $Name"
    }
}

Write-Host ""
Write-Host "  Connecting Azure CLI and GitHub CLI" -ForegroundColor Cyan
Write-Host ""

Require-Command 'gh'
Require-Command 'git'

# -- Azure CLI authentication ---------------------------------------------------

Write-Step "Authenticating to Azure"
$azureValidated = $true
if (Get-Command az -ErrorAction SilentlyContinue) {
    az account show 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $subName = az account show --query name -o tsv 2>$null
        Write-Ok "Azure CLI authentication complete. (subscription: $subName)"
    } else {
        az login
        if ($LASTEXITCODE -eq 0) {
            $subName = az account show --query name -o tsv 2>$null
            Write-Ok "Azure CLI authentication complete. (subscription: $subName)"
        } else {
            Write-Fail "Azure login did not complete. Run 'az login' and try again."
            exit 1
        }
    }
} else {
    # Not fatal: forking needs only gh. But this script is documented as
    # validating Azure auth, and the checklist's success criterion is "no red
    # [FAIL] lines" -- so without a flag carried to the summary, a student with
    # no Azure CLI ticks the box here and only discovers the gap in Section G.
    $script:azureValidated = $false
    Write-Warn "Azure CLI not found. Install it from Section C and re-run."
}

# -- GitHub CLI authentication --------------------------------------------------

Write-Step "Authenticating to GitHub CLI"
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "GitHub CLI is not authenticated. Run 'gh auth login' from Section D first."
    exit 1
}
$ghUser = gh api user --jq .login 2>$null
if (-not $ghUser) {
    Write-Fail "Could not read GitHub username. Re-run 'gh auth login' and try again."
    exit 1
}
Write-Ok "GitHub CLI authentication complete. (signed in as @$ghUser)"

# -- Fork -----------------------------------------------------------------------

$upstreamOwner = ($UpstreamRepo -split '/', 2)[0]
$repoName      = ($UpstreamRepo -split '/', 2)[1]
if (-not $repoName -or -not $upstreamOwner) {
    Write-Fail "UpstreamRepo must be in 'owner/name' format."
    exit 1
}
$forkRepo = "$ghUser/$repoName"
$forkUrl  = "https://github.com/$forkRepo"

Write-Step "Forking the lab repo to your account"
$forkWarning = ''

if ($ghUser -eq $upstreamOwner) {
    # You cannot fork a repo into the account that already owns it. Say so
    # plainly instead of reporting the upstream back as "your fork".
    Write-Ok "You own $UpstreamRepo already - no fork needed."
    Write-Info "Clone it directly in Section F; the workflows and secrets are yours."
} else {
    # Ask what the repo IS, not merely whether the name is taken. A student who
    # already has an unrelated repo called $repoName would otherwise be told
    # their fork was ready, and every later step -- gh repo set-default, the
    # OIDC federated credential, the deploy workflows -- would target a repo
    # with none of the lab's workflows in it.
    #
    # This only ever WARNS. It runs before anything else in the workshop, so a
    # wrong answer here -- an unexpected payload, a gh version that renders
    # 'parent' differently -- must not be able to stop a classroom at step one.
    # Being noisy about a repo that is actually fine costs a scary message;
    # blocking on one costs the session.
    gh repo view $forkRepo --json name 2>$null | Out-Null
    $repoExists = ($LASTEXITCODE -eq 0)

    if ($repoExists) {
        $existing = $null
        try   { $existing = gh repo view $forkRepo --json isFork,parent 2>$null | ConvertFrom-Json }
        catch { $existing = $null }

        if (-not $existing -or $null -eq $existing.isFork) {
            # Could not tell. Say so and carry on rather than guessing either way.
            Write-Ok "Fork is ready at: $forkUrl"
            Write-Warn "(Could not confirm it is a fork of $UpstreamRepo - continuing anyway.)"
        }
        else {
            $parent = if ($existing.parent) { "$($existing.parent.owner.login)/$($existing.parent.name)" } else { '' }
            if ($existing.isFork -and $parent -eq $UpstreamRepo) {
                Write-Ok "Fork is ready at: $forkUrl"
            }
            elseif ($existing.isFork) {
                Write-Warn "$forkRepo exists but is a fork of '$parent', not $UpstreamRepo."
                Write-Warn "Rename or delete it and re-run, or the labs will deploy from the wrong repo."
                $script:forkWarning = "$forkRepo is a fork of '$parent', not $UpstreamRepo."
            }
            else {
                Write-Warn "$forkRepo exists but is NOT a fork of $UpstreamRepo."
                Write-Warn "The labs would deploy from a repo with none of the workshop's workflows."
                Write-Warn "Rename or delete that repo and re-run this script."
                $script:forkWarning = "$forkRepo is not a fork of $UpstreamRepo."
            }
        }
    }
    else {
        gh repo fork $UpstreamRepo --clone=false --remote=false
        if ($LASTEXITCODE -ne 0) {
            # Pre-existing behaviour, deliberately unchanged: no fork exists and
            # none could be created, so there is genuinely nothing to go on with.
            Write-Fail "Fork failed. Check your GitHub permissions and try again."
            exit 1
        }
        Write-Ok "Fork is ready at: $forkUrl"
    }
}
Write-Info "Use that URL in Section F of the checklist when cloning your copy of the repo."

# -- GitHub Copilot CLI extension -----------------------------------------------

Write-Step "Installing/verifying GitHub Copilot CLI"
$extList = gh extension list 2>$null
if ($extList -match 'gh-copilot') {
    Write-Ok "gh copilot command is available."
} else {
    gh extension install github/gh-copilot 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "gh copilot command is available."
    } else {
        Write-Warn "Extension install failed. Run: gh extension install github/gh-copilot"
    }
}
Write-Ok "Authentication helper completed."

# -- Summary --------------------------------------------------------------------

if ($forkWarning) {
    Write-Host ""
    Write-Warn "READ THIS BEFORE SECTION F:"
    Write-Warn "  $forkWarning"
    Write-Warn "Nothing was blocked, but cloning the URL below would give you the wrong"
    Write-Warn "repo - no lab workflows, and Setup-Oidc.ps1 would wire Azure up to it."
    Write-Warn "Rename or delete that repo, then re-run this script."
}

if (-not $azureValidated) {
    Write-Host ""
    Write-Warn "Azure CLI was NOT validated - a step this script skipped."
    Write-Warn "Install it (Section C) and run 'az login' (Section D) before Section G,"
    Write-Warn "or Setup-Oidc.ps1 will fail there. Forking above was unaffected."
}

Write-Host ""
Write-Host "  Done. Copy this URL and use it in Section F (Clone):" -ForegroundColor Cyan
Write-Host "    $forkUrl" -ForegroundColor White
Write-Host ""
Write-Host "  Then open the checklist for the clone step:" -ForegroundColor DarkGray
$wikiUrl = 'https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist-Part-2'
Write-Host "  $wikiUrl" -ForegroundColor DarkGray
Write-Host ""
