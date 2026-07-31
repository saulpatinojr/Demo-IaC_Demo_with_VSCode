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
    repo in the next step (Section E.2 in the checklist).

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

# ── Azure CLI authentication ───────────────────────────────────────────────────

Write-Step "Authenticating to Azure"
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
    Write-Warn "Azure CLI not found. Install it from Section C and re-run."
}

# ── GitHub CLI authentication ──────────────────────────────────────────────────

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

# ── Fork ───────────────────────────────────────────────────────────────────────

$repoName = ($UpstreamRepo -split '/', 2)[1]
if (-not $repoName) {
    Write-Fail "UpstreamRepo must be in 'owner/name' format."
    exit 1
}
$forkRepo = "$ghUser/$repoName"
$forkUrl  = "https://github.com/$forkRepo"

Write-Step "Forking the lab repo to your account"
gh repo view $forkRepo --json name --jq .name 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Fork is ready at: $forkUrl"
} else {
    gh repo fork $UpstreamRepo --clone=false --remote=false
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Fork failed. Check your GitHub permissions and try again."
        exit 1
    }
    Write-Ok "Fork is ready at: $forkUrl"
}
Write-Info "Use that URL in Section E.2 of the checklist when cloning your copy of the repo."

# ── GitHub Copilot CLI extension ───────────────────────────────────────────────

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

# ── Summary ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Done. Copy this URL and use it in the next step (E.2 - Clone):" -ForegroundColor Cyan
Write-Host "    $forkUrl" -ForegroundColor White
Write-Host ""
Write-Host "  Then open the checklist for the clone step:" -ForegroundColor DarkGray
$wikiUrl = 'https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Start-Here-Checklist-Part-2'
Write-Host "  $wikiUrl" -ForegroundColor DarkGray
Write-Host ""
