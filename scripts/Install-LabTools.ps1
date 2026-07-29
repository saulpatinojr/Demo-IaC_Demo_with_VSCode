<#
.SYNOPSIS
    One-command lab workstation setup for the IaC with GitHub Copilot workshop.

.DESCRIPTION
    Installs everything a participant needs and leaves the workstation ready to use:

      SOFTWARE
        Git for Windows        winget Git.Git
        GitHub Desktop         winget GitHub.GitHubDesktop
        Visual Studio Code     winget Microsoft.VisualStudioCode
        Azure CLI (az)         winget Microsoft.AzureCLI
        GitHub CLI (gh)        winget GitHub.cli
        PowerShell 7 (pwsh)    winget Microsoft.PowerShell
        Windows Terminal       winget Microsoft.WindowsTerminal
        Bicep CLI              az bicep install  (after Azure CLI)

      VS CODE EXTENSIONS
        Bicep                  ms-azuretools.vscode-bicep
        GitHub Copilot         GitHub.copilot
        GitHub Copilot Chat    GitHub.copilot-chat
        Azure CLI Tools        ms-vscode.azurecli
        GitHub Actions         github.vscode-github-actions

      CONFIGURATION
        git config  user.name / user.email / sensible defaults
        VS Code     auto-save, format on save, PS7 as default terminal
        gh copilot  CLI extension (installed after gh auth login)

      SIGN-IN (interactive, opens browser)
        gh auth login   — GitHub (+ installs gh copilot extension after)
        az login        — Azure (then prompts to select the right subscription)

      NEXT STEPS REMINDER (printed at the end — require the GUI)
        Open VS Code → Ctrl+Alt+I → sign in to Copilot Chat
        Fork + clone the lab repo → run Setup-Oidc.ps1

    The script is idempotent: already-installed tools are skipped. Re-running
    after an interrupted install is safe.

.PARAMETER GitName
    Your full name for git config. Prompted interactively if not supplied.

.PARAMETER GitEmail
    Your email for git config. Prompted interactively if not supplied.

.PARAMETER SkipLogin
    Skip the interactive az / gh login steps at the end (useful if already logged in).

.EXAMPLE
    ./scripts/Install-LabTools.ps1
    Fully guided — prompts for name + email, then opens browser for Azure + GitHub login.

.EXAMPLE
    ./scripts/Install-LabTools.ps1 -GitName "Alice Smith" -GitEmail "alice@example.com"

.EXAMPLE
    ./scripts/Install-LabTools.ps1 -SkipLogin
    Install tools only; skip the login prompts.

.NOTES
    Requires: Windows 10/11 with winget, local Administrator rights.
    Run from PowerShell 5 or PowerShell 7 — the script works in both.
#>
[CmdletBinding()]
param(
    [string] $GitName,
    [string] $GitEmail,
    [switch] $SkipLogin
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Banner($text) {
    $line = '─' * ($text.Length + 4)
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

function Write-Step($msg)  { Write-Host "`n  ▶  $msg" -ForegroundColor White }
function Write-Ok($msg)    { Write-Host "     ✅  $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "     ⏭   $msg" -ForegroundColor DarkGray }
function Write-Warn($msg)  { Write-Host "     ⚠️   $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "     ❌  $msg" -ForegroundColor Red }

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

function Is-Installed($cmd) {
    $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Winget-Install($id, $name) {
    Write-Step "$name"
    $result = winget list --id $id --exact 2>$null
    if ($LASTEXITCODE -eq 0 -and ($result -match $id)) {
        Write-Skip "$name already installed"
        return
    }
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Write-Ok "$name installed" }
    else                      { Write-Warn "$name install returned exit $LASTEXITCODE (may still have succeeded)" }
}

# ── Admin check ───────────────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Banner "Lab Workstation Setup — IaC with GitHub Copilot Workshop"

if (-not $isAdmin) {
    Write-Warn "Not running as Administrator. Some installs may fail."
    Write-Warn "Right-click PowerShell → 'Run as administrator' and re-run this script."
    $cont = Read-Host "  Continue anyway? [y/N]"
    if ($cont -notmatch '^[Yy]') { exit 1 }
}

# ── winget availability check ─────────────────────────────────────────────────

Write-Step "Checking winget"
if (-not (Is-Installed 'winget')) {
    Write-Fail "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}
$wingetVer = (winget --version) -replace '[^0-9.]',''
Write-Ok "winget $wingetVer available"

# ── Software installs ─────────────────────────────────────────────────────────

Write-Banner "Installing Software"

Winget-Install 'Git.Git'                  'Git for Windows'
Winget-Install 'GitHub.GitHubDesktop'     'GitHub Desktop'
Winget-Install 'Microsoft.VisualStudioCode' 'Visual Studio Code'
Winget-Install 'Microsoft.AzureCLI'       'Azure CLI (az)'
Winget-Install 'GitHub.cli'               'GitHub CLI (gh)'
Winget-Install 'Microsoft.PowerShell'     'PowerShell 7 (pwsh)'
Winget-Install 'Microsoft.WindowsTerminal' 'Windows Terminal'

# Refresh PATH so all newly installed tools are reachable in this session
Refresh-Path

# ── Bicep CLI ─────────────────────────────────────────────────────────────────

Write-Step "Bicep CLI (via az bicep install)"
if (Is-Installed 'az') {
    az bicep install 2>&1 | Out-Null
    $bicepVer = az bicep version --query version -o tsv 2>$null
    if ($bicepVer) { Write-Ok "Bicep CLI $bicepVer" }
    else           { Write-Ok "Bicep CLI installed (run 'az bicep version' to verify)" }
} else {
    Write-Warn "az CLI not on PATH yet — run 'az bicep install' after reopening the terminal"
}

# ── VS Code extensions ────────────────────────────────────────────────────────

Write-Banner "Installing VS Code Extensions"

$codeCmd = 'code'
if (-not (Is-Installed $codeCmd)) {
    # VS Code sometimes isn't on PATH until the terminal is restarted
    $codePaths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )
    $codeCmd = $codePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $codeCmd) {
        Write-Warn "VS Code 'code' command not on PATH yet. Extensions will be installed on next run."
        $codeCmd = $null
    }
}

if ($codeCmd) {
    $extensions = @(
        @{ Id = 'ms-azuretools.vscode-bicep';    Name = 'Bicep' },
        @{ Id = 'GitHub.copilot';                Name = 'GitHub Copilot' },
        @{ Id = 'GitHub.copilot-chat';           Name = 'GitHub Copilot Chat' },
        @{ Id = 'ms-vscode.azurecli';            Name = 'Azure CLI Tools' },
        @{ Id = 'github.vscode-github-actions';  Name = 'GitHub Actions' }
    )
    foreach ($ext in $extensions) {
        Write-Step "$($ext.Name)"
        $installed = & $codeCmd --list-extensions 2>$null | Where-Object { $_ -ieq $ext.Id }
        if ($installed) {
            Write-Skip "$($ext.Name) already installed"
        } else {
            & $codeCmd --install-extension $ext.Id --force 2>&1 | Out-Null
            Write-Ok "$($ext.Name) installed"
        }
    }
} else {
    Write-Warn "Skipped VS Code extensions — re-run this script after reopening the terminal."
}

# ── VS Code settings ──────────────────────────────────────────────────────────

Write-Banner "Configuring VS Code Settings"

$settingsDir  = "$env:APPDATA\Code\User"
$settingsFile = "$settingsDir\settings.json"
$null = New-Item -ItemType Directory -Path $settingsDir -Force

$labSettings = @{
    "files.autoSave"                           = "onFocusChange"
    "editor.formatOnSave"                      = $true
    "editor.formatOnPaste"                     = $true
    "editor.wordWrap"                          = "on"
    "editor.tabSize"                           = 2
    "editor.renderWhitespace"                  = "boundary"
    "terminal.integrated.defaultProfile.windows" = "PowerShell"
    "terminal.integrated.profiles.windows"     = @{
        "PowerShell" = @{
            "source" = "PowerShell"
            "icon"   = "terminal-powershell"
        }
    }
    "git.enableSmartCommit"                    = $true
    "git.confirmSync"                          = $false
    "github.copilot.enable"                    = @{ "*" = $true }
    "bicep.enableSurveys"                      = $false
    "workbench.startupEditor"                  = "none"
    "security.workspace.trust.untrustedFiles"  = "open"
}

# Merge with existing settings (don't clobber user customisations)
$existing = @{}
if (Test-Path $settingsFile) {
    try {
        $raw = Get-Content $settingsFile -Raw
        # Strip JSON comments before parsing
        $raw = $raw -replace '(?m)^\s*//.*$', '' -replace ',\s*\}', '}'
        $existing = $raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
        if ($null -eq $existing) { $existing = @{} }
    } catch { $existing = @{} }
}
foreach ($k in $labSettings.Keys) { $existing[$k] = $labSettings[$k] }
$existing | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding utf8

Write-Ok "VS Code settings written to $settingsFile"

# ── Git configuration ─────────────────────────────────────────────────────────

Write-Banner "Configuring Git"

if (-not (Is-Installed 'git')) {
    Refresh-Path
}

if (Is-Installed 'git') {
    # Prompt for identity if not supplied
    if (-not $GitName) {
        $current = git config --global user.name 2>$null
        if ($current) {
            Write-Skip "git user.name already set to: $current"
            $GitName = $current
        } else {
            $GitName = Read-Host "  Enter your full name for git commits (e.g. Alice Smith)"
        }
    }
    if (-not $GitEmail) {
        $current = git config --global user.email 2>$null
        if ($current) {
            Write-Skip "git user.email already set to: $current"
            $GitEmail = $current
        } else {
            $GitEmail = Read-Host "  Enter your email for git commits (use your GitHub email)"
        }
    }

    git config --global user.name  $GitName
    git config --global user.email $GitEmail

    # Sensible defaults
    git config --global init.defaultBranch     main
    git config --global core.autocrlf          input      # LF in repo, CRLF checkout on Windows
    git config --global core.editor            "code --wait"
    git config --global pull.rebase            false
    git config --global credential.helper      manager    # Git Credential Manager
    git config --global push.autoSetupRemote   true
    git config --global fetch.prune            true

    Write-Ok "git config: user.name  = $GitName"
    Write-Ok "git config: user.email = $GitEmail"
    Write-Ok "git config: defaultBranch=main, autocrlf=input, editor=code, credential.helper=manager"
} else {
    Write-Warn "git not on PATH — reopen the terminal and re-run to configure git identity."
}

# ── Interactive logins ────────────────────────────────────────────────────────

if (-not $SkipLogin) {
    Write-Banner "Signing In"

    # ── GitHub CLI ──
    Write-Step "GitHub CLI (gh auth login)"
    Write-Host "     A browser window will open. Sign in with your GitHub account." -ForegroundColor DarkCyan
    if (Is-Installed 'gh') {
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Skip "Already signed in to GitHub CLI"
        } else {
            gh auth login --web --git-protocol https
            if ($LASTEXITCODE -eq 0) { Write-Ok "GitHub CLI authenticated" }
            else                     { Write-Warn "gh auth login did not complete — run 'gh auth login' manually" }
        }
    } else {
        Write-Warn "gh not on PATH — reopen terminal and run: gh auth login"
    }

    # ── GitHub Copilot CLI extension (requires gh auth) ──
    Write-Step "GitHub Copilot CLI extension (gh extension install github/gh-copilot)"
    if (Is-Installed 'gh') {
        $extList = gh extension list 2>$null
        if ($extList -match 'gh-copilot') {
            Write-Skip "gh copilot extension already installed"
        } else {
            gh extension install github/gh-copilot 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Ok "gh copilot extension installed (try: gh copilot explain 'list files')" }
            else                     { Write-Warn "Extension install failed — run manually: gh extension install github/gh-copilot" }
        }
    }

    # ── Azure CLI ──
    Write-Step "Azure CLI (az login)"
    Write-Host "     A browser window will open. Sign in with your Azure account." -ForegroundColor DarkCyan
    if (Is-Installed 'az') {
        $alreadyIn = $false
        az account show 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $alreadyIn = $true
            $subName = az account show --query name -o tsv 2>$null
            Write-Skip "Already signed in to Azure — subscription: $subName"
        } else {
            az login
            if ($LASTEXITCODE -eq 0) {
                $alreadyIn = $true
                Write-Ok "Azure CLI authenticated"
            } else {
                Write-Warn "az login did not complete — run 'az login' manually"
            }
        }

        # Subscription selection — show list if more than one is available
        if ($alreadyIn) {
            $subsJson = az account list --query "[].{Name:name,Id:id,Default:isDefault}" -o json 2>$null
            $subs = $subsJson | ConvertFrom-Json
            if ($subs.Count -gt 1) {
                Write-Step "Select the target Azure subscription"
                for ($i = 0; $i -lt $subs.Count; $i++) {
                    $marker = if ($subs[$i].Default) { '  ◀ current default' } else { '' }
                    $color  = if ($subs[$i].Default) { 'Green' } else { 'White' }
                    Write-Host ("     [{0}]  {1}`n          {2}{3}" -f ($i + 1), $subs[$i].Name, $subs[$i].Id, $marker) -ForegroundColor $color
                }
                $choice = Read-Host "  Enter number to select (press Enter to keep current default)"
                if ($choice -match '^\d+$') {
                    $idx = [int]$choice - 1
                    if ($idx -ge 0 -and $idx -lt $subs.Count) {
                        az account set --subscription $subs[$idx].Id | Out-Null
                        Write-Ok "Active subscription: $($subs[$idx].Name)"
                    } else {
                        Write-Warn "Invalid selection — keeping current default"
                    }
                } else {
                    Write-Skip "Keeping default: $(az account show --query name -o tsv 2>$null)"
                }
            } else {
                Write-Ok "Subscription: $(az account show --query name -o tsv 2>$null)"
            }
        }
    } else {
        Write-Warn "az not on PATH — reopen terminal and run: az login"
    }
}

# ── Final verification ────────────────────────────────────────────────────────

Write-Banner "Verification"

$checks = @(
    @{ Name = 'git';        Cmd = { git --version } },
    @{ Name = 'gh';         Cmd = { gh --version } },
    @{ Name = 'az';         Cmd = { az --version | Select-Object -First 1 } },
    @{ Name = 'az bicep';   Cmd = { az bicep version 2>$null } },
    @{ Name = 'pwsh';       Cmd = { pwsh --version } },
    @{ Name = 'code';       Cmd = { code --version | Select-Object -First 1 } }
)

$allGood = $true
foreach ($c in $checks) {
    try {
        $ver = & $c.Cmd 2>$null
        if ($ver) { Write-Ok "$($c.Name.PadRight(10)) $ver" }
        else      { Write-Warn "$($c.Name.PadRight(10)) installed but 'version' returned empty"; $allGood = $false }
    } catch {
        Write-Fail "$($c.Name.PadRight(10)) NOT FOUND on PATH"
        $allGood = $false
    }
}

Write-Host ""
if (-not $SkipLogin) {
    Write-Step "Login status"
    try {
        $ghUser = gh api user --jq .login 2>$null
        if ($ghUser) { Write-Ok "GitHub:  signed in as @$ghUser" }
        else         { Write-Warn "GitHub:  not authenticated — run: gh auth login" }
    } catch { Write-Warn "GitHub:  not authenticated — run: gh auth login" }

    try {
        $azSub  = az account show --query name -o tsv 2>$null
        if ($azSub) { Write-Ok "Azure:   signed in — subscription: $azSub" }
        else        { Write-Warn "Azure:   not authenticated — run: az login" }
    } catch { Write-Warn "Azure:   not authenticated — run: az login" }
}

Write-Host ""
if ($allGood) {
    Write-Host "  🎉  All tools verified." -ForegroundColor Green
} else {
    Write-Host "  ⚠️   Some tools were not found on PATH." -ForegroundColor Yellow
    Write-Host "       Close this terminal, open a fresh PowerShell 7 window, and re-run:" -ForegroundColor Yellow
    Write-Host "       ./scripts/Install-LabTools.ps1 -SkipLogin" -ForegroundColor Cyan
}

Write-Banner "Next Steps"
Write-Host "  Complete these manually — they require the GUI:" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  1. Open VS Code" -ForegroundColor White
Write-Host "     → Press  Ctrl+Alt+I  to open Copilot Chat" -ForegroundColor White
Write-Host "     → Sign in with your GitHub account when prompted" -ForegroundColor White
Write-Host "     → Confirm the Copilot icon appears in the sidebar" -ForegroundColor White
Write-Host ""
Write-Host "  2. Fork + clone the lab repo" -ForegroundColor White
Write-Host "     → https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode  (click Fork)" -ForegroundColor DarkCyan
Write-Host "     → GitHub Desktop: File → Clone repository → pick your fork" -ForegroundColor White
Write-Host "     → Open the cloned folder in VS Code (accept the recommended extensions prompt)" -ForegroundColor White
Write-Host ""
Write-Host "  3. Run the OIDC setup (from inside the cloned repo):" -ForegroundColor White
Write-Host "     ./scripts/Setup-Oidc.ps1 -ResourceGroup `"rg-lab-<yourname>`" -Prefix `"<yourname>`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  4. Head to the workshop wiki to start Lab 1:" -ForegroundColor White
Write-Host "     https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki" -ForegroundColor DarkCyan
Write-Host ""
