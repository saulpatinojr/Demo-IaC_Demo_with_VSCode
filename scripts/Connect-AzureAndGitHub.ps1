[CmdletBinding()]
param(
    [switch]$SkipAzLogin,
    [switch]$SkipGhLogin
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

function Write-Banner([string]$text) {
    $line = '=' * ($text.Length + 8)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host "  === $text ===" -ForegroundColor Yellow
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host ""
}
function Write-Step([string]$message) { Write-Host ""; Write-Host "  > $message" -ForegroundColor White }
function Write-Ok([string]$message) { Write-Host "    [OK] $message" -ForegroundColor Green }
function Write-Warn([string]$message) { Write-Host "    [WARN] $message" -ForegroundColor Yellow }
function Write-Fail([string]$message) { Write-Host "    [FAIL] $message" -ForegroundColor Red }

Write-Banner 'Authentication Setup'
Write-Step 'Connecting Azure CLI and GitHub CLI'

if (-not $SkipAzLogin) {
    Write-Step 'Authenticating to Azure'
    if (Get-Command az -ErrorAction SilentlyContinue) {
        az login --use-device-code
        if ($LASTEXITCODE -ne 0) {
            Write-Fail 'Azure login did not complete successfully.'
            exit $LASTEXITCODE
        }
        Write-Ok 'Azure CLI authentication complete.'
    } else {
        Write-Warn 'Azure CLI was not found in PATH. Please install it first.'
    }
} else {
    Write-Warn 'Skipping Azure login because -SkipAzLogin was provided.'
}

if (-not $SkipGhLogin) {
    Write-Step 'Authenticating to GitHub CLI'
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status --hostname github.com 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            gh auth login -h github.com --web
            if ($LASTEXITCODE -ne 0) {
                Write-Fail 'GitHub login did not complete successfully.'
                exit $LASTEXITCODE
            }
        }
        Write-Ok 'GitHub CLI authentication complete.'
    } else {
        Write-Warn 'GitHub CLI was not found in PATH. Please install it first.'
    }
} else {
    Write-Warn 'Skipping GitHub login because -SkipGhLogin was provided.'
}

Write-Ok 'Authentication helper completed.'
