<#
.SYNOPSIS
<<<<<<< HEAD
    Loads your lab environment variables from lab-settings.csv into the current session.

.DESCRIPTION
    Reads lab-settings.csv from the repo root and sets the environment variables the
    lab commands need — so you can copy-paste terminal commands without editing them.

    Run this once at the start of every terminal session. Use -Persist to survive restarts.

    To get started:
      1. Copy  lab-settings.csv.example  to  lab-settings.csv  in the repo root.
      2. Fill in your values (AZURE_RESOURCE_GROUP, AZURE_PREFIX, etc.).
      3. Run this script: ./scripts/Load-LabSettings.ps1

    lab-settings.csv is in .gitignore — your values are never committed.

.PARAMETER Persist
    Also saves all variables to the current user's permanent environment so they
    survive terminal restarts. Run once with -Persist, then without it afterwards.

.PARAMETER CsvPath
    Path to the CSV file. Defaults to lab-settings.csv in the repo root (auto-detected
    from the script's location regardless of your current working directory).

.EXAMPLE
    ./scripts/Load-LabSettings.ps1            # load for this session only
    ./scripts/Load-LabSettings.ps1 -Persist   # load + save permanently

.EXAMPLE
    # Verify what was loaded:
    $env:AZURE_RESOURCE_GROUP
    $env:AZURE_PREFIX
#>
[CmdletBinding()]
param(
    [switch] $Persist,
    [string] $CsvPath
=======
    Loads your lab values from lab-settings.csv into the environment variables the
    .bicepparam files read — so you fill one file instead of typing variables.

.DESCRIPTION
    1. Copy lab-settings.csv.example to lab-settings.csv (repo root) and fill it in
       (open it in Excel or VS Code — one row of values).
    2. Run this script to load those values for your terminal:
           ./scripts/Load-LabSettings.ps1
       Add -Persist to also keep them for future terminals:
           ./scripts/Load-LabSettings.ps1 -Persist

    The .bicepparam files stay unchanged, so the GitHub Actions / OIDC path is
    unaffected — this only makes the local az deploy path fill-in-a-file simple.

.PARAMETER Path
    Path to the CSV. Defaults to lab-settings.csv in the repo root.

.PARAMETER Persist
    Also save the values as user environment variables (survive new terminals).
#>
[CmdletBinding()]
param(
    [string] $Path,
    [switch] $Persist
>>>>>>> origin/main
)

$ErrorActionPreference = 'Stop'

<<<<<<< HEAD
# ── Locate the CSV ──────────────────────────────────────────────────────────

if (-not $CsvPath) {
    # Default: lab-settings.csv next to the repo root (one level above scripts/)
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $CsvPath  = Join-Path $repoRoot 'lab-settings.csv'
}

if (-not (Test-Path $CsvPath)) {
    $example = $CsvPath -replace 'lab-settings\.csv$', 'lab-settings.csv.example'
    Write-Host ""
    Write-Host "  ❌  lab-settings.csv not found at:" -ForegroundColor Red
    Write-Host "      $CsvPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "  ➡️   Copy the example file and fill in your values:" -ForegroundColor Yellow
    Write-Host "      Copy-Item '$example' '$CsvPath'" -ForegroundColor Cyan
    Write-Host "      Then open it in VS Code:  code '$CsvPath'" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# ── Parse the CSV ───────────────────────────────────────────────────────────

$rows = Import-Csv $CsvPath
if ($rows.Count -eq 0) {
    Write-Host "  ❌  lab-settings.csv is empty. Fill in your values." -ForegroundColor Red
    exit 1
}
$settings = $rows[0]  # only the first data row matters

# ── Required columns ────────────────────────────────────────────────────────

$required = @('AZURE_RESOURCE_GROUP', 'AZURE_PREFIX', 'AZURE_LOCATION')
$missing  = $required | Where-Object { -not $settings.$_ -or $settings.$_ -match '^<' }
if ($missing) {
    Write-Host ""
    Write-Host "  ❌  Fill in these columns in lab-settings.csv:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
    Write-Host ""
    exit 1
}

# ── Set environment variables ────────────────────────────────────────────────

$loaded = @()
$settings.PSObject.Properties | ForEach-Object {
    $name  = $_.Name.Trim()
    $value = $_.Value.Trim()
    if ($name -and $value -and $value -notmatch '^<') {
        [System.Environment]::SetEnvironmentVariable($name, $value, 'Process')
        if ($Persist) {
            [System.Environment]::SetEnvironmentVariable($name, $value, 'User')
        }
        $loaded += $name
    }
}

# ── Summary ─────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ✅  Lab settings loaded" -ForegroundColor Green
Write-Host ""
Write-Host ("  {0,-30} {1}" -f "AZURE_RESOURCE_GROUP", $env:AZURE_RESOURCE_GROUP) -ForegroundColor Cyan
Write-Host ("  {0,-30} {1}" -f "AZURE_PREFIX",         $env:AZURE_PREFIX)         -ForegroundColor Cyan
Write-Host ("  {0,-30} {1}" -f "AZURE_LOCATION",       $env:AZURE_LOCATION)       -ForegroundColor Cyan
if ($env:ALERT_EMAIL) {
    Write-Host ("  {0,-30} {1}" -f "ALERT_EMAIL", $env:ALERT_EMAIL) -ForegroundColor Cyan
}
Write-Host ""

if ($Persist) {
    Write-Host "  📌  Variables saved permanently (User scope) — no need to re-run after restarting." -ForegroundColor DarkGray
} else {
    Write-Host "  ℹ️   Session only — re-run this script if you open a new terminal." -ForegroundColor DarkGray
    Write-Host "      Add -Persist to save permanently." -ForegroundColor DarkGray
}
Write-Host ""
=======
function Write-Ok($m)   { Write-Host "    [OK] $m"   -ForegroundColor Green }
function Write-Fail($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }
function Write-Info($m) { Write-Host "    [INFO] $m" -ForegroundColor DarkCyan }

if (-not $Path) {
    $Path = Join-Path (Split-Path $PSScriptRoot -Parent) 'lab-settings.csv'
}

if (-not (Test-Path $Path)) {
    Write-Fail "Not found: $Path"
    Write-Host "         Copy lab-settings.csv.example to lab-settings.csv and fill in your values." -ForegroundColor Yellow
    exit 1
}

$row = Import-Csv -Path $Path | Select-Object -First 1
if (-not $row) {
    Write-Fail "$Path has a header but no data row."
    exit 1
}

$required = @('AZURE_PREFIX', 'AZURE_LOCATION', 'AZURE_RESOURCE_GROUP', 'VM_ADMIN_PASSWORD', 'SQL_ADMIN_PASSWORD')
$missing  = @()

Write-Host ""
Write-Host "  Loading lab settings from $Path" -ForegroundColor White

foreach ($prop in $row.PSObject.Properties) {
    $name  = $prop.Name
    $value = "$($prop.Value)".Trim()

    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($required -contains $name) { $missing += $name }
        continue
    }

    Set-Item -Path "env:$name" -Value $value
    if ($Persist) { [Environment]::SetEnvironmentVariable($name, $value, 'User') }

    $shown = if ($name -match 'PASSWORD') { '********' } else { $value }
    Write-Ok ("{0,-22} = {1}" -f $name, $shown)
}

if ($missing.Count -gt 0) {
    Write-Fail "Missing required value(s): $($missing -join ', ')"
    Write-Host "         Fill them in $Path and re-run." -ForegroundColor Yellow
    exit 1
}

$scope = if ($Persist) { 'this terminal and future terminals' } else { 'this terminal only' }
Write-Host ""
Write-Info "Loaded for $scope."
Write-Host "  Now deploy any lab, e.g.:" -ForegroundColor DarkCyan
Write-Host '    az deployment group create --resource-group $env:AZURE_RESOURCE_GROUP --parameters labs/L1-hub-spoke/main.bicepparam' -ForegroundColor Cyan
>>>>>>> origin/main
