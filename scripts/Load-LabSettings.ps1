<#
.SYNOPSIS
    Loads your lab values from lab-settings.csv into the environment variables the
    .bicepparam files read - so you fill in one file instead of typing variables.

.DESCRIPTION
    1. Copy lab-settings.csv.example to lab-settings.csv (repo root) and fill it in
       (open it in Excel or VS Code - it is one row of values).
    2. Run this script to load those values into your terminal:
           ./scripts/Load-LabSettings.ps1
       Add -Persist to also keep them for future terminals:
           ./scripts/Load-LabSettings.ps1 -Persist

    The .bicepparam files stay unchanged, so the GitHub Actions / OIDC path is
    unaffected - this only makes the local "az deployment group create" path a
    fill-in-a-file exercise.

    lab-settings.csv is in .gitignore, so your values are never committed.

    Values are validated before they are exported: missing entries, leftover
    <placeholder> text, and the ChangeMe-* example passwords are all rejected
    here rather than failing several minutes into a deployment.

.PARAMETER Path
    Path to the CSV. Defaults to lab-settings.csv in the repo root (resolved from
    the script's own location, so your working directory does not matter).

.PARAMETER Persist
    Also save the values as user environment variables so they survive new
    terminals.

    THIS WRITES TO YOUR MACHINE. On Windows the values -- including
    VM_ADMIN_PASSWORD and SQL_ADMIN_PASSWORD -- are stored in the registry
    under HKCU\Environment, in plain text, and stay there until removed. That
    is a deliberate lab convenience, not a pattern to copy at work. Remove them
    with -Clear when you are done.

    WINDOWS ONLY. .NET supports the User environment scope on Windows alone; on
    macOS and Linux the write silently does nothing. The script detects this and
    tells you rather than claiming values were saved. lab-settings.csv is the
    real persistence on those platforms -- just re-run this script per terminal.

.PARAMETER Clear
    Remove the values -Persist wrote, and unset them in this terminal. Needs no
    CSV, so it works even after you have deleted lab-settings.csv. For signing
    out of az and gh as well, see ./scripts/Clear-LabCredentials.ps1.

.EXAMPLE
    ./scripts/Load-LabSettings.ps1            # load for this terminal only
.EXAMPLE
    ./scripts/Load-LabSettings.ps1 -Persist   # load + save for future terminals
.EXAMPLE
    ./scripts/Load-LabSettings.ps1 -Clear     # remove what -Persist saved
.EXAMPLE
    # Verify what was loaded:
    $env:AZURE_RESOURCE_GROUP
    $env:AZURE_PREFIX
#>
[CmdletBinding()]
param(
    [Alias('CsvPath')]
    [string] $Path,
    [switch] $Persist,
    [switch] $Clear
)

$ErrorActionPreference = 'Stop'

function Write-Ok($m)   { Write-Host "    [OK] $m"   -ForegroundColor Green }
function Write-Fail($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }
function Write-Info($m) { Write-Host "    [INFO] $m" -ForegroundColor DarkCyan }
function Write-Warn($m) { Write-Host "    [WARN] $m" -ForegroundColor Yellow }

# Every lab reads these; ALERT_EMAIL is optional (L1.3 falls back to a default).
$required = @(
    'AZURE_PREFIX'
    'AZURE_LOCATION'
    'AZURE_RESOURCE_GROUP'
    'VM_ADMIN_PASSWORD'
    'SQL_ADMIN_PASSWORD'
)

# Every name this script is capable of persisting. Fixed rather than read from
# the CSV so -Clear still works after the CSV has been deleted.
$persistable = $required + @('ALERT_EMAIL')

# .NET supports the User environment scope on Windows only. Elsewhere the write
# is accepted and silently discarded, so -Persist would print "saved for future
# terminals" and the next terminal would have nothing.
$canPersist = $IsWindows -or ($null -eq $IsWindows)   # $IsWindows is absent on PS 5.1, which is Windows

# Opposite intents. -Clear exits early, so accepting both would silently do the
# reverse of what someone who fat-fingered the flag expected.
if ($Clear -and $Persist) {
    Write-Host ""
    Write-Fail '-Persist and -Clear do opposite things; pass one or the other.'
    Write-Host "         -Persist  save the values to this machine" -ForegroundColor DarkGray
    Write-Host "         -Clear    remove values already saved" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

# ---- -Clear: remove what -Persist wrote ------------------------------------
if ($Clear) {
    Write-Host ""
    Write-Host "  Clearing saved lab settings" -ForegroundColor White
    $removed = 0
    foreach ($name in $persistable) {
        # $null -ne, not truthiness: a variable set to an empty string is falsy
        # but still present in the registry. Testing truth would leave it there
        # while reporting nothing was saved.
        if ($canPersist -and $null -ne [Environment]::GetEnvironmentVariable($name, 'User')) {
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
            Write-Ok "removed saved $name"
            $removed++
        }
        if (Test-Path "env:$name") { Remove-Item "env:$name" -ErrorAction SilentlyContinue }
    }
    if ($removed -eq 0) {
        Write-Info 'nothing was saved to this machine - cleared this terminal only.'
    } else {
        Write-Info "removed $removed saved value(s); this terminal is cleared too."
    }
    Write-Host "         Open a NEW terminal to confirm they are gone." -ForegroundColor DarkGray
    Write-Host "         To sign out of Azure and GitHub as well:" -ForegroundColor DarkGray
    Write-Host "           ./scripts/Clear-LabCredentials.ps1" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

if (-not $Path) {
    $Path = Join-Path (Split-Path $PSScriptRoot -Parent) 'lab-settings.csv'
}

if (-not (Test-Path $Path)) {
    $example = $Path -replace 'lab-settings\.csv$', 'lab-settings.csv.example'
    Write-Host ""
    Write-Fail "Not found: $Path"
    Write-Host "         Copy the example file and fill in your values:" -ForegroundColor Yellow
    Write-Host "           Copy-Item '$example' '$Path'" -ForegroundColor Cyan
    Write-Host "           code '$Path'" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

$row = Import-Csv -Path $Path | Select-Object -First 1
if (-not $row) {
    Write-Fail "$Path has a header row but no data row."
    exit 1
}

Write-Host ""
Write-Host "  Loading lab settings from $Path" -ForegroundColor White

# ---- Collect and validate before exporting anything ------------------------
# Nothing is exported until every required value passes, so a partial edit can
# never leave you with a half-configured terminal.
$values   = @{}
$problems = @()

foreach ($prop in $row.PSObject.Properties) {
    $name  = $prop.Name.Trim()
    $value = "$($prop.Value)".Trim()
    if (-not $name) { continue }

    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($required -contains $name) { $problems += "$name is empty" }
        continue
    }

    # Placeholder text straight from the example file.
    if ($value -match '^<.*>$') {
        $problems += "$name still contains the placeholder '$value'"
        continue
    }
    if ($value -like 'ChangeMe-*') {
        $problems += "$name still contains the example password - set a real one"
        continue
    }

    $values[$name] = $value
}

foreach ($name in $required) {
    if (-not $values.ContainsKey($name) -and -not ($problems -match "^$name ")) {
        $problems += "$name column is missing from the CSV header"
    }
}

# prefix feeds resource names and is @maxLength(12) in every main.bicep.
if ($values.ContainsKey('AZURE_PREFIX')) {
    $prefix = $values['AZURE_PREFIX']
    if ($prefix.Length -gt 12) {
        $problems += "AZURE_PREFIX '$prefix' is $($prefix.Length) characters - the templates allow at most 12"
    }
    elseif ($prefix -notmatch '^[a-z0-9][a-z0-9-]*$') {
        $problems += "AZURE_PREFIX '$prefix' should be lowercase letters, digits and hyphens only"
    }
}

if ($problems.Count -gt 0) {
    Write-Host ""
    Write-Fail "lab-settings.csv is not ready:"
    $problems | ForEach-Object { Write-Host "           - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "         Fix them in $Path and re-run." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ---- Export ----------------------------------------------------------------
$didPersist = $Persist -and $canPersist

foreach ($name in ($values.Keys | Sort-Object)) {
    $value = $values[$name]
    Set-Item -Path "env:$name" -Value $value
    if ($didPersist) { [Environment]::SetEnvironmentVariable($name, $value, 'User') }

    $shown = if ($name -match 'PASSWORD') { '********' } else { $value }
    Write-Ok ("{0,-22} = {1}" -f $name, $shown)
}

$scope = if ($didPersist) { 'this terminal and future terminals' } else { 'this terminal only' }
Write-Host ""
Write-Info "Loaded for $scope."

if ($Persist -and -not $canPersist) {
    # Saying nothing here would be the worst outcome: the values look saved and
    # the next terminal has none of them.
    Write-Host ""
    Write-Warn "-Persist does nothing on macOS or Linux - only Windows has a user"
    Write-Warn "environment store for .NET to write to. NOTHING was saved."
    Write-Host "         lab-settings.csv is your persistence: just re-run" -ForegroundColor DarkGray
    Write-Host "           ./scripts/Load-LabSettings.ps1" -ForegroundColor Cyan
    Write-Host "         in each new terminal. That also keeps your passwords out of" -ForegroundColor DarkGray
    Write-Host "         a shell profile, which is the safer habit anyway." -ForegroundColor DarkGray
}
elseif ($didPersist) {
    Write-Host ""
    Write-Warn "SAVED TO THIS MACHINE - lab convenience, not a work habit."
    Write-Warn "VM_ADMIN_PASSWORD and SQL_ADMIN_PASSWORD are now in the registry"
    Write-Warn "(HKCU\Environment) in plain text, readable by anything you run,"
    Write-Warn "and they stay there until you remove them."
    Write-Host "         Remove them when you are done:" -ForegroundColor DarkGray
    Write-Host "           ./scripts/Load-LabSettings.ps1 -Clear" -ForegroundColor Cyan
    Write-Host "         Also signing out of Azure and GitHub:" -ForegroundColor DarkGray
    Write-Host "           ./scripts/Clear-LabCredentials.ps1" -ForegroundColor Cyan
}
else {
    Write-Host "         Re-run with -Persist to keep these in future terminals" -ForegroundColor DarkGray
    Write-Host "         (Windows only, and it stores passwords on disk)." -ForegroundColor DarkGray
}
Write-Host "  Now deploy any lab, e.g.:" -ForegroundColor DarkCyan
Write-Host '    az deployment group create --resource-group $env:AZURE_RESOURCE_GROUP --parameters curriculum/L1.1-core-deployment/main.bicepparam' -ForegroundColor Cyan
Write-Host ""
