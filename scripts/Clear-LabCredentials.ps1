<#
.SYNOPSIS
    Removes everything this workshop left on YOUR MACHINE -- sign-in tokens,
    saved settings, and the passwords file. Deletes nothing in Azure.

.DESCRIPTION
    Running the labs signs you in to two CLIs and (optionally) saves settings
    to your user profile. On a classroom laptop that gets reimaged this does
    not matter. On your own machine it does, so this script puts it back.

    What it removes:

      Azure CLI     az logout, clearing the token cache in ~/.azure
      GitHub CLI    gh auth logout, clearing the token in the gh config
      Lab settings  the AZURE_* / *_PASSWORD values that
                    Load-LabSettings.ps1 -Persist wrote (Windows only)
      Settings file lab-settings.csv, which holds your passwords in plain text

    What it does NOT touch, deliberately:

      - Anything deployed in Azure. Use Cleanup-Labs.ps1 for that, FIRST --
        once you are signed out you cannot tear resources down, and they
        keep billing.
      - The Entra app registration. That is Cleanup-Labs.ps1 -RemoveOidc.
      - GitHub Desktop, VS Code, or Git Credential Manager. Each keeps its own
        store; this script reports them rather than reaching into them.

.PARAMETER KeepSettingsFile
    Leave lab-settings.csv in place. Use this if you intend to run the labs
    again and only want to sign out.

.PARAMETER SkipAzure
    Do not run az logout.

.PARAMETER SkipGitHub
    Do not run gh auth logout.

.PARAMETER WhatIf
    Show what would be removed, change nothing. Start here.

.EXAMPLE
    ./scripts/Clear-LabCredentials.ps1 -WhatIf
    Preview. Recommended first run.

.EXAMPLE
    ./scripts/Clear-LabCredentials.ps1
    Sign out of both CLIs, clear saved settings, delete lab-settings.csv.

.EXAMPLE
    ./scripts/Clear-LabCredentials.ps1 -KeepSettingsFile
    Sign out but keep your values for a later run.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $KeepSettingsFile,
    [switch] $SkipAzure,
    [switch] $SkipGitHub
)

$ErrorActionPreference = 'Stop'

function Write-Banner($text) {
    $line = '=' * ($text.Length + 8)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host "  === $text ===" -ForegroundColor Yellow
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host ""
}
function Write-Step($m) { Write-Host ""; Write-Host "  > $m" -ForegroundColor White }
function Write-Ok($m)   { Write-Host "    [OK] $m"   -ForegroundColor Green }
function Write-Skip($m) { Write-Host "    [SKIP] $m" -ForegroundColor DarkGray }
function Write-Warn($m) { Write-Host "    [WARN] $m" -ForegroundColor Yellow }
function Write-Info($m) { Write-Host "    [INFO] $m" -ForegroundColor DarkCyan }

Write-Banner 'Clear lab credentials from this machine'

# Signing out first would strand any still-deployed resources: no token, no
# teardown, and they bill until someone notices. Worth one check.
Write-Step 'Checking for resources still deployed'
$rg = $env:AZURE_RESOURCE_GROUP
$uncertain = $false      # could not establish what is deployed
$stillUp   = $false      # confirmed something is deployed

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Skip 'cannot check - az is not installed'
    $uncertain = $true
} elseif (-not $rg) {
    Write-Skip 'cannot check - AZURE_RESOURCE_GROUP is not set'
    $uncertain = $true
} else {
    $count = az resource list --resource-group $rg --query 'length(@)' -o tsv 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Never fold this into the "none found" branch. The query fails when you
        # are signed out, the group is gone, or you lack permission -- and
        # reporting "no resources" there would be a reassurance handed out
        # moments before the sign-out that makes teardown impossible.
        Write-Warn "could NOT check '$rg' - signed out, group missing, or no permission."
        $uncertain = $true
    } elseif ($count -and [int]$count -gt 0) {
        Write-Warn "$count resource(s) still deployed in '$rg'."
        $stillUp = $true
    } else {
        Write-Ok "no resources found in '$rg'"
    }
}

if ($stillUp -or $uncertain) {
    $lead = if ($stillUp) { 'Tear them down BEFORE signing out' } else { 'Confirm the group is empty BEFORE signing out' }
    Write-Warn "$lead - afterwards you cannot,"
    Write-Warn 'and Firewall, Bastion, Front Door and SQL bill while they run:'
    $shown = if ($rg) { $rg } else { '<your resource group>' }
    Write-Host "           ./scripts/Cleanup-Labs.ps1 -ResourceGroup `"$shown`"" -ForegroundColor Cyan
    Write-Host ""
    if (-not $WhatIfPreference) {
        $go = Read-Host '    Continue clearing credentials anyway? (y/N)'
        if ($go -notmatch '^[Yy]') {
            Write-Info 'Stopped. Nothing was changed.'
            exit 0
        }
    }
}

# ---- Azure CLI -------------------------------------------------------------
Write-Step 'Azure CLI'
if ($SkipAzure) {
    Write-Skip '-SkipAzure specified'
} elseif (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Skip 'az is not installed'
} else {
    az account show -o none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Skip 'already signed out'
    } elseif ($PSCmdlet.ShouldProcess('Azure CLI', 'Sign out and clear token cache')) {
        az logout 2>$null | Out-Null
        # az logout drops the account but can leave the MSAL cache behind.
        az account clear 2>$null | Out-Null
        Write-Ok 'signed out; token cache cleared'
    } else {
        Write-Skip 'would sign out of Azure CLI'
    }
}

# ---- GitHub CLI ------------------------------------------------------------
Write-Step 'GitHub CLI'
if ($SkipGitHub) {
    Write-Skip '-SkipGitHub specified'
} elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Skip 'gh is not installed'
} else {
    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Skip 'already signed out'
    } elseif ($PSCmdlet.ShouldProcess('GitHub CLI', 'Sign out')) {
        gh auth logout --hostname github.com 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'signed out' }
        else { Write-Warn 'gh auth logout did not complete - run it yourself: gh auth logout' }
    } else {
        Write-Skip 'would sign out of GitHub CLI'
    }
}

# ---- Saved lab settings ----------------------------------------------------
Write-Step 'Saved lab settings'
$persistable = @(
    'AZURE_PREFIX', 'AZURE_LOCATION', 'AZURE_RESOURCE_GROUP',
    'VM_ADMIN_PASSWORD', 'SQL_ADMIN_PASSWORD', 'ALERT_EMAIL'
)
# .NET only has a User environment scope on Windows; elsewhere -Persist was
# always a no-op, so there is nothing stored to remove.
$canPersist = $IsWindows -or ($null -eq $IsWindows)
$cleared = 0
$found   = 0
foreach ($name in $persistable) {
    # $null -ne, not truthiness: a value of "" is falsy but still present in the
    # registry, and skipping it would leave an entry behind while reporting that
    # nothing was saved.
    if ($canPersist -and $null -ne [Environment]::GetEnvironmentVariable($name, 'User')) {
        $found++
        if ($PSCmdlet.ShouldProcess("saved $name", 'Remove')) {
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
            $cleared++
        } else {
            Write-Skip "would remove saved $name"
        }
    }
    if (Test-Path "env:$name") { Remove-Item "env:$name" -ErrorAction SilentlyContinue }
}
# $found, not $cleared, drives the summary: under -WhatIf nothing is removed, so
# reporting on $cleared would say "nothing was saved" while listing values it
# had just found.
if ($cleared -gt 0)       { Write-Ok "removed $cleared saved value(s) from this machine" }
elseif ($found -gt 0)     { Write-Skip "$found saved value(s) found - none removed (dry run)" }
elseif (-not $canPersist) { Write-Skip 'nothing to remove (-Persist never stored anything on this platform)' }
else                      { Write-Skip 'nothing was saved to this machine' }

# ---- lab-settings.csv ------------------------------------------------------
Write-Step 'lab-settings.csv'
$csv = Join-Path (Split-Path $PSScriptRoot -Parent) 'lab-settings.csv'
if ($KeepSettingsFile) {
    Write-Skip '-KeepSettingsFile specified - your passwords remain in that file'
} elseif (-not (Test-Path $csv)) {
    Write-Skip 'not present'
} elseif ($PSCmdlet.ShouldProcess($csv, 'Delete')) {
    Remove-Item $csv -Force
    Write-Ok 'deleted (it held your VM and SQL passwords in plain text)'
} else {
    Write-Skip "would delete $csv"
}

# ---- Things this script will not reach into --------------------------------
Write-Step 'Left for you'
Write-Info 'These keep their own credential stores. Sign out in the app if this'
Write-Info 'is a shared or personal machine:'
Write-Host "           GitHub Desktop   File -> Options -> Accounts -> Sign out" -ForegroundColor DarkGray
Write-Host "           VS Code          Accounts icon -> Sign out (GitHub / Copilot)" -ForegroundColor DarkGray
Write-Host "           Git credentials  Windows Credential Manager -> github.com" -ForegroundColor DarkGray

Write-Banner 'Done'
if ($WhatIfPreference) {
    Write-Warn 'DRY RUN - nothing was changed. Re-run without -WhatIf.'
} else {
    Write-Ok 'This machine no longer holds the lab tokens or settings.'
    Write-Info 'Nothing in Azure was deleted. Resources, if any, are still there.'
}
Write-Host ""
