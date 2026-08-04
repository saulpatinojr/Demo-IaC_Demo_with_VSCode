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
    terminals. Run once with -Persist, then without it afterwards.

.EXAMPLE
    ./scripts/Load-LabSettings.ps1            # load for this terminal only
.EXAMPLE
    ./scripts/Load-LabSettings.ps1 -Persist   # load + save for future terminals
.EXAMPLE
    # Verify what was loaded:
    $env:AZURE_RESOURCE_GROUP
    $env:AZURE_PREFIX
#>
[CmdletBinding()]
param(
    [Alias('CsvPath')]
    [string] $Path,
    [switch] $Persist
)

$ErrorActionPreference = 'Stop'

function Write-Ok($m)   { Write-Host "    [OK] $m"   -ForegroundColor Green }
function Write-Fail($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }
function Write-Info($m) { Write-Host "    [INFO] $m" -ForegroundColor DarkCyan }

# Every lab reads these; ALERT_EMAIL is optional (L3 falls back to a default).
$required = @(
    'AZURE_PREFIX'
    'AZURE_LOCATION'
    'AZURE_RESOURCE_GROUP'
    'VM_ADMIN_PASSWORD'
    'SQL_ADMIN_PASSWORD'
)

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
foreach ($name in ($values.Keys | Sort-Object)) {
    $value = $values[$name]
    Set-Item -Path "env:$name" -Value $value
    if ($Persist) { [Environment]::SetEnvironmentVariable($name, $value, 'User') }

    $shown = if ($name -match 'PASSWORD') { '********' } else { $value }
    Write-Ok ("{0,-22} = {1}" -f $name, $shown)
}

$scope = if ($Persist) { 'this terminal and future terminals' } else { 'this terminal only' }
Write-Host ""
Write-Info "Loaded for $scope."
if (-not $Persist) {
    Write-Host "         Re-run with -Persist to keep these in future terminals." -ForegroundColor DarkGray
}
Write-Host "  Now deploy any lab, e.g.:" -ForegroundColor DarkCyan
Write-Host '    az deployment group create --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L1-hub-spoke/main.bicepparam' -ForegroundColor Cyan
Write-Host ""
