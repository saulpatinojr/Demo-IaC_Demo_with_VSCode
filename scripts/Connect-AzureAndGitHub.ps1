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
function Write-Info([string]$message) { Write-Host "    [INFO] $message" -ForegroundColor DarkCyan }

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

        Write-Step 'Forking the lab repo to your account'
        $forkResult = gh repo fork saulpatinojr/Demo-IaC_Demo_with_VSCode --clone=false 2>&1
        $forkText   = ($forkResult | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -or $forkText -match 'Already forked|already exists') {
            $ghUser = (gh api user --jq '.login' 2>$null)
            Write-Ok "Fork is ready at: https://github.com/$ghUser/Demo-IaC_Demo_with_VSCode"
            Write-Info 'Use that URL in Section E of the checklist when cloning your copy of the repo.'
        } else {
            Write-Warn 'Fork did not complete automatically. Open https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode and click Fork manually, then continue.'
        }

        Write-Step 'Installing/verifying GitHub Copilot CLI'
        $copilotCheck = (gh copilot --version 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0 -and $copilotCheck -notmatch 'not installed|Would you like to install') {
            Write-Ok 'gh copilot command is available.'
        } else {
            # gh copilot is a built-in stub that requires answering Y to install its payload.
            Write-Info 'Triggering GitHub Copilot CLI installation (auto-answering install prompt)...'
            $inputFile = New-TemporaryFile
            try {
                Set-Content -Path $inputFile.FullName -Value 'Y'
                $proc = Start-Process -FilePath 'gh' -ArgumentList @('copilot', '--version') `
                    -RedirectStandardInput $inputFile.FullName `
                    -NoNewWindow -PassThru -Wait
            } finally {
                Remove-Item $inputFile.FullName -Force -ErrorAction SilentlyContinue
            }
            $copilotCheck2 = (gh copilot --version 2>&1) -join "`n"
            if ($LASTEXITCODE -eq 0 -and $copilotCheck2 -notmatch 'not installed|Would you like to install') {
                Write-Ok 'gh copilot command is available.'
            } else {
                Write-Warn 'gh copilot setup did not complete. Open a new terminal and run: gh copilot --version'
            }
        }
    } else {
        Write-Warn 'GitHub CLI was not found in PATH. Please install it first.'
    }
} else {
    Write-Warn 'Skipping GitHub login because -SkipGhLogin was provided.'
}

Write-Ok 'Authentication helper completed.'
