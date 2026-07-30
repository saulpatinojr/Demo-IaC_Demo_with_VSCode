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
        gh auth login   - GitHub (+ installs gh copilot extension after)
        az login        - Azure (then prompts to select the right subscription)

      NEXT STEPS REMINDER (printed at the end - require the GUI)
        Open VS Code -> Ctrl+Alt+I -> sign in to Copilot Chat
        Fork + clone the lab repo -> run Setup-Oidc.ps1

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
    Fully guided - prompts for name + email, then opens browser for Azure + GitHub login.

.EXAMPLE
    ./scripts/Install-LabTools.ps1 -GitName "Alice Smith" -GitEmail "alice@example.com"

.EXAMPLE
    ./scripts/Install-LabTools.ps1 -SkipLogin
    Install tools only; skip the login prompts.

.NOTES
    Requires: Windows 10/11 with winget, local Administrator rights.
    No execution-policy bypass command is required for this workshop.
    Run from PowerShell 5 or PowerShell 7 - the script works in both.
#>
[CmdletBinding()]
param(
    [string] $GitName,
    [string] $GitEmail,
    [switch] $SkipLogin
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
$MissingExtensionsCount = 0

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Banner($text) {
    $line = '=' * ($text.Length + 8)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host "  === $text ===" -ForegroundColor Yellow
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host ""
}

function Write-Step($msg) {
    Write-Host ""
    Write-Host "  > $msg" -ForegroundColor White
}
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "    [SKIP] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg)  { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "    [FAIL] $msg" -ForegroundColor Red }
function Write-Info($msg)  { Write-Host "    [INFO] $msg" -ForegroundColor DarkCyan }

function Get-BicepVersionFromAz {
    try {
        $raw = az bicep version 2>$null
        if (-not $raw) { return $null }
        $combined = ($raw | Out-String).Trim()
        if ($combined -match 'Bicep CLI version\s+([0-9]+\.[0-9]+\.[0-9]+)') {
            return $Matches[1]
        }
        return $combined
    } catch {
        return $null
    }
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

function Is-Installed($cmd) {
    $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Invoke-ProcessQuiet {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $ArgumentList
    )

    $tmpOut = New-TemporaryFile
    $tmpErr = New-TemporaryFile
    try {
        $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -PassThru -Wait -RedirectStandardOutput $tmpOut.FullName -RedirectStandardError $tmpErr.FullName
        $stdout = @()
        $stderr = @()
        if (Test-Path $tmpOut.FullName) { $stdout = @(Get-Content -Path $tmpOut.FullName -ErrorAction SilentlyContinue) }
        if (Test-Path $tmpErr.FullName) { $stderr = @(Get-Content -Path $tmpErr.FullName -ErrorAction SilentlyContinue) }

        [pscustomobject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    } finally {
        Remove-Item $tmpOut.FullName -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Get-CodeExtensions([string] $codeCmdPath) {
    $result = Invoke-ProcessQuiet -FilePath $codeCmdPath -ArgumentList @('--list-extensions')
    if ($result.ExitCode -ne 0) {
        Write-Warn "Failed to list VS Code extensions (exit $($result.ExitCode))"
        return @()
    }
    return @($result.StdOut | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Install-CodeExtension([string] $codeCmdPath, [string] $extensionId, [string] $extensionName) {
    $result = Invoke-ProcessQuiet -FilePath $codeCmdPath -ArgumentList @('--install-extension', $extensionId, '--force')
    if ($result.ExitCode -eq 0) {
        Write-Ok "$extensionName installed"
        return $true
    }

    $errSummary = ($result.StdErr | Select-Object -First 1)
    if (-not $errSummary) { $errSummary = 'no error text returned' }
    Write-Warn "$extensionName install returned exit $($result.ExitCode): $errSummary"
    return $false
}

function Ensure-CodeDesktopShortcut([string] $codeCmdPath) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Visual Studio Code.lnk'
    if (Test-Path $shortcutPath) {
        Write-Skip 'VS Code desktop shortcut already exists'
        return
    }

    $codeExe = $null
    if ($codeCmdPath -like '*.cmd') {
        $candidate = $codeCmdPath -replace '\\bin\\code\.cmd$', '\\Code.exe'
        if (Test-Path $candidate) { $codeExe = $candidate }
    }
    if (-not $codeExe) {
        $candidates = @(
            "$env:LOCALAPPDATA\\Programs\\Microsoft VS Code\\Code.exe",
            "$env:ProgramFiles\\Microsoft VS Code\\Code.exe"
        )
        $codeExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if (-not $codeExe) {
        Write-Warn 'Could not determine VS Code executable path for desktop shortcut'
        return
    }

    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $codeExe
        $shortcut.WorkingDirectory = Split-Path $codeExe -Parent
        $shortcut.IconLocation = "$codeExe,0"
        $shortcut.Save()
        Write-Ok 'Created VS Code desktop shortcut'
    } catch {
        Write-Warn "Failed to create VS Code desktop shortcut: $($_.Exception.Message)"
    }
}

function Winget-Install($id, $name) {
    Write-Step "$name"

    # Avoid `winget list` pre-checks here: on some lab images it can block for
    # a long time with no visible output. Let `winget install --no-upgrade`
    # handle idempotency instead.
    $arguments = @(
        'install',
        '--id', $id,
        '--exact',
        '--no-upgrade',
        '--silent',
        '--disable-interactivity',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--source', 'winget'
    )

    $maxInstallSeconds = 1800
    $heartbeatSeconds = 20
    $start = Get-Date
    $nextHeartbeat = $start.AddSeconds($heartbeatSeconds)

    Write-Info "$name install/verify started (this can take a few minutes)."
    $proc = Start-Process -FilePath 'winget' -ArgumentList $arguments -NoNewWindow -PassThru

    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 2
        $proc.Refresh()

        $now = Get-Date
        if ($now -ge $nextHeartbeat) {
            $elapsed = [int]($now - $start).TotalSeconds
            Write-Info "$name install still running (${elapsed}s elapsed)..."
            $nextHeartbeat = $now.AddSeconds($heartbeatSeconds)
        }

        if (($now - $start).TotalSeconds -ge $maxInstallSeconds) {
            try { $proc.Kill() } catch { }
            Write-Fail "$name install exceeded $maxInstallSeconds seconds and was stopped. Re-run to retry."
            return
        }
    }

    if ($proc.ExitCode -eq 0) {
        Write-Ok "$name installed or already present"
        return
    }

    # Some winget outcomes are non-zero but expected for idempotent runs.
    $exitCode = [int]$proc.ExitCode
    $exitHex = ('0x{0:X8}' -f ($exitCode -band 0xFFFFFFFF))
    $allText = @($result.StdOut + $result.StdErr) -join "`n"

    if ($allText -match 'already installed|installation cancelled|No available upgrade found|No applicable upgrade found') {
        Write-Skip "$name already installed ($exitHex)"
        return
    }

    Write-Warn "$name install returned exit $exitCode ($exitHex)"
}

# ── Admin check ───────────────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Banner "Lab Workstation Setup - IaC with GitHub Copilot Workshop"

if (-not $isAdmin) {
    Write-Fail "Not running as Administrator. This script requires elevation for reliable one-shot setup."
    Write-Warn "Right-click PowerShell -> 'Run as administrator' and re-run this script."
    exit 1
}

# ── winget availability check ─────────────────────────────────────────────────

Write-Step "Checking winget"
if (-not (Is-Installed 'winget')) {
    Write-Fail "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}
$wingetVer = (winget --version) -replace '[^0-9.]',''
Write-Ok "winget $wingetVer available"
Write-Info 'Installs run in silent mode; heartbeat messages will print during long operations.'

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
    $existingBicepVer = Get-BicepVersionFromAz
    if ($existingBicepVer) {
        Write-Skip "Bicep CLI already available: $existingBicepVer"
    } else {
        # Run az as a child process so warning text on stderr does not surface
        # as a terminating PowerShell error in older hosts.
        $azInstallProc = Start-Process -FilePath 'az' -ArgumentList @('bicep', 'install', '--only-show-errors') -NoNewWindow -PassThru -Wait
        if ($azInstallProc.ExitCode -ne 0) {
            Write-Warn "az bicep install returned exit $($azInstallProc.ExitCode); continuing with version check"
        }

        $bicepVer = Get-BicepVersionFromAz
        if ($bicepVer) {
            Write-Ok "Bicep CLI $bicepVer"
        } else {
            Write-Warn "Bicep install attempted but version could not be detected. Reopen terminal and run: az bicep version"
        }
    }
} else {
    Write-Warn "az CLI not on PATH yet - run 'az bicep install' after reopening the terminal"
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
    Write-Step 'Ensuring VS Code desktop shortcut'
    Ensure-CodeDesktopShortcut $codeCmd

    $extensions = @(
        @{ Id = 'ms-azuretools.vscode-bicep';    Name = 'Bicep' },
        @{ Id = 'GitHub.copilot';                Name = 'GitHub Copilot' },
        @{ Id = 'GitHub.copilot-chat';           Name = 'GitHub Copilot Chat' },
        @{ Id = 'ms-vscode.azurecli';            Name = 'Azure CLI Tools' },
        @{ Id = 'github.vscode-github-actions';  Name = 'GitHub Actions' }
    )

    $installedIds = Get-CodeExtensions $codeCmd
    foreach ($ext in $extensions) {
        Write-Step "$($ext.Name)"
        $installed = $installedIds | Where-Object { $_ -ieq $ext.Id }
        if ($installed) {
            Write-Skip "$($ext.Name) already installed"
        } else {
            $didInstall = Install-CodeExtension -codeCmdPath $codeCmd -extensionId $ext.Id -extensionName $ext.Name
            if ($didInstall) {
                $installedIds += $ext.Id
            }
        }
    }

    Write-Step "Verifying VS Code extensions"
    $installedIds = Get-CodeExtensions $codeCmd
    $missing = @($extensions | Where-Object { $installedIds -notcontains $_.Id })
    if ($missing.Count -eq 0) {
        Write-Ok 'All required VS Code extensions are installed'
    } else {
        foreach ($m in $missing) {
            Write-Warn "Missing extension: $($m.Id) ($($m.Name))"
        }
        Write-Warn "Open a fresh terminal and run ./scripts/Authenticate-LabTools.ps1 to finish sign-in and extension setup."
    }

    Set-Variable -Name MissingExtensionsCount -Value $missing.Count -Scope Script
} else {
    Write-Warn "Skipped VS Code extensions - re-run this script after reopening the terminal."
    Set-Variable -Name MissingExtensionsCount -Value 5 -Scope Script
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
    Write-Warn "git not on PATH - reopen the terminal and re-run to configure git identity."
}

# ── Authentication follow-up ────────────────────────────────────────────────

Write-Banner "Authentication Setup"
Write-Step "Authentication is deferred to a follow-up script"
Write-Host "  Fresh desktops are expected to be signed out, so this installer focuses on setting up tools first." -ForegroundColor DarkCyan
Write-Host "  Run this after installation completes:" -ForegroundColor DarkCyan
Write-Host "    ./scripts/Connect-AzureAndGitHub.ps1" -ForegroundColor Cyan
Write-Host "  That script will sign you into GitHub and Azure and install the Copilot CLI extension." -ForegroundColor DarkCyan

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
if ($MissingExtensionsCount -gt 0) {
    $allGood = $false
}

Write-Host ""
if ($allGood) {
    Write-Host "  [DONE]  Tool installation completed." -ForegroundColor Green
} else {
    Write-Host "  [WARN]  Some setup steps need a fresh terminal or a follow-up run." -ForegroundColor Yellow
    Write-Host "       Open a new PowerShell window and run:" -ForegroundColor Yellow
    Write-Host "       ./scripts/Connect-AzureAndGitHub.ps1" -ForegroundColor Cyan
}

Write-Banner "Next Steps"
Write-Host "  Follow these steps in order:" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  1) Open VS Code and confirm Copilot Chat works" -ForegroundColor White
Write-Host "     - Press Ctrl+Alt+I to open Copilot Chat" -ForegroundColor White
Write-Host "     - Sign in with GitHub when prompted" -ForegroundColor White
Write-Host "     - Send a test message to confirm chat is active" -ForegroundColor White
Write-Host ""
Write-Host "  2) Make sure you are in YOUR forked repo" -ForegroundColor White
Write-Host "     - Repo to fork: https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode" -ForegroundColor DarkCyan
Write-Host "     - Clone your fork locally (GitHub Desktop or gh repo clone)" -ForegroundColor White
Write-Host "     - Open that cloned folder in VS Code" -ForegroundColor White
Write-Host ""
Write-Host "  3) Sign in to GitHub and Azure from this repo:" -ForegroundColor White
Write-Host "     ./scripts/Connect-AzureAndGitHub.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  4) Configure GitHub Actions access to Azure (OIDC):" -ForegroundColor White
Write-Host "     - If your instructor already pre-configured this, skip to step 5" -ForegroundColor White
Write-Host "     - Otherwise run:" -ForegroundColor White
Write-Host "       ./scripts/Setup-Oidc.ps1 -ResourceGroup `"rg-lab-<yourname>`" -Prefix `"<yourname>`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  5) Start Lab 1 in the wiki:" -ForegroundColor White
Write-Host "     https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki" -ForegroundColor DarkCyan
Write-Host ""

