<#
.SYNOPSIS
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
)

$ErrorActionPreference = 'Stop'

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
