<#
.SYNOPSIS
    Connects lab prerequisites by creating your fork and cloning it locally.

.DESCRIPTION
    This script uses your signed-in GitHub CLI session to:
      1) Confirm your GitHub username
      2) Create your fork of the workshop repo (if it does not exist)
      3) Clone your fork to your local machine (if it is not already cloned)
      4) Add the instructor repo as the 'upstream' remote

    It is safe to re-run (idempotent): existing fork, clone, and upstream remote
    are detected and reused.

.PARAMETER UpstreamRepo
    Source repo to fork (owner/name). Defaults to the workshop repo.

.PARAMETER CloneRoot
    Folder where the fork is cloned. Defaults to the current user's Desktop.

.PARAMETER SkipClone
    Creates/verifies the fork but skips local clone operations.

.PARAMETER OpenCode
    Opens the cloned repo in VS Code at the end.

.EXAMPLE
    ./scripts/Connect-AzureAndGitHub.ps1

.EXAMPLE
    ./scripts/Connect-AzureAndGitHub.ps1 -CloneRoot "$HOME\source" -OpenCode
#>
[CmdletBinding()]
param(
    [string] $UpstreamRepo = 'saulpatinojr/Demo-IaC_Demo_with_VSCode',
    [string] $CloneRoot = (Join-Path $HOME 'Desktop'),
    [switch] $SkipClone,
    [switch] $OpenCode
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n> $msg" -ForegroundColor White }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  [INFO] $msg" -ForegroundColor DarkCyan }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Fail "Required command '$Name' was not found on PATH."
        throw "Missing command: $Name"
    }
}

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Connect Azure + GitHub (fork and clone setup) " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

Require-Command 'gh'
Require-Command 'git'

Write-Step "Validating GitHub CLI authentication"
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "GitHub CLI is not authenticated."
    Write-Host "  Run: gh auth login" -ForegroundColor Cyan
    exit 1
}
$ghUser = gh api user --jq .login 2>$null
if (-not $ghUser) {
    Write-Fail "Could not detect GitHub username from gh."
    exit 1
}
Write-Ok "Authenticated as @$ghUser"

Write-Step "Checking Azure CLI authentication (required later for Setup-Oidc)"
if (Get-Command az -ErrorAction SilentlyContinue) {
    az account show 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $subName = az account show --query name -o tsv 2>$null
        Write-Ok "Azure CLI authenticated (subscription: $subName)"
    } else {
        Write-Warn "Azure CLI is not authenticated yet. Run 'az login' before Setup-Oidc."
    }
} else {
    Write-Warn "Azure CLI was not found on PATH. Install and sign in before Setup-Oidc."
}

$repoName = ($UpstreamRepo -split '/', 2)[1]
if (-not $repoName) {
    Write-Fail "UpstreamRepo must be in 'owner/name' format."
    exit 1
}
$forkRepo = "$ghUser/$repoName"
$forkUrl = "https://github.com/$forkRepo"

Write-Step "Ensuring fork exists: $forkRepo"
gh repo view $forkRepo --json name --jq .name 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Fork already exists: $forkUrl"
} else {
    gh repo fork $UpstreamRepo --clone=false --remote=false
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to create fork for $UpstreamRepo."
        exit 1
    }
    Write-Ok "Fork created: $forkUrl"
}

$targetPath = Join-Path $CloneRoot $repoName

if (-not $SkipClone) {
    Write-Step "Ensuring local clone exists"
    if (-not (Test-Path $CloneRoot)) {
        $null = New-Item -Path $CloneRoot -ItemType Directory -Force
    }

    if (Test-Path (Join-Path $targetPath '.git')) {
        Write-Ok "Clone already exists: $targetPath"
    } elseif (Test-Path $targetPath) {
        Write-Fail "Target path exists but is not a git repo: $targetPath"
        Write-Host "  Choose a different CloneRoot or remove that folder and re-run." -ForegroundColor Cyan
        exit 1
    } else {
        gh repo clone $forkRepo $targetPath
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Clone failed."
            exit 1
        }
        Write-Ok "Cloned: $targetPath"
    }

    Write-Step "Configuring 'upstream' remote"
    $upstreamUrl = git -C $targetPath remote get-url upstream 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstreamUrl) {
        if ($upstreamUrl -notmatch [regex]::Escape($UpstreamRepo)) {
            git -C $targetPath remote set-url upstream "https://github.com/$UpstreamRepo.git"
            Write-Ok "Updated upstream remote to https://github.com/$UpstreamRepo.git"
        } else {
            Write-Ok "Upstream remote already configured"
        }
    } else {
        git -C $targetPath remote add upstream "https://github.com/$UpstreamRepo.git"
        Write-Ok "Added upstream remote"
    }
}

Write-Host ""
Write-Host "Next step inside your forked repo:" -ForegroundColor Cyan
if (-not $SkipClone) {
    Write-Host "  cd `"$targetPath`"" -ForegroundColor White
}
Write-Host '  ./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>" -WhatIf' -ForegroundColor White
Write-Host '  ./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-<yourname>" -Prefix "<yourname>"' -ForegroundColor White

if ($OpenCode -and -not $SkipClone) {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        code $targetPath | Out-Null
        Write-Info "Opened VS Code: $targetPath"
    } else {
        Write-Warn "VS Code command 'code' not found on PATH."
    }
}
