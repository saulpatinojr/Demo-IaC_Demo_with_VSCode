<#
.SYNOPSIS
    Delete the workshop's Azure resources (and optionally the OIDC identity).

.DESCRIPTION
    The labs create real, billable resources — Azure Firewall, Bastion, Front
    Door and SQL all bill while idle. This script tears them down in the correct
    order (L4 -> L1, because later labs depend on earlier ones) and can also
    remove the Entra app + role assignment created by Setup-Oidc.ps1.

    ALWAYS preview first:   ./scripts/Cleanup-Labs.ps1 -WhatIf

.PARAMETER Prefix
    Resource-name prefix used when deploying. Default: iacdemo. Resource groups
    are rg-<prefix>-l1 .. rg-<prefix>-l4.

.PARAMETER Level
    Which labs to remove: All (default), L4, L3, L2, or L1. Deleting a single
    level does NOT delete the ones it depends on.

.PARAMETER RemoveOidc
    Also delete the Entra app registration named by -AppName and its role
    assignment. Off by default so you can redeploy without re-running setup.

.PARAMETER AppName
    Entra app to remove when -RemoveOidc is set. Default: iac-demo-oidc.

.PARAMETER WhatIf
    Show what would be deleted without deleting anything.

.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -WhatIf
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1                 # delete all lab resource groups
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -Level L2       # delete only rg-iacdemo-l2
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -RemoveOidc     # full teardown incl. OIDC identity
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $Prefix = 'iacdemo',
    [ValidateSet('All', 'L4', 'L3', 'L2', 'L1')]
    [string] $Level = 'All',
    [switch] $RemoveOidc,
    [string] $AppName = 'iac-demo-oidc'
)

$ErrorActionPreference = 'Stop'
function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Write-Skip($m) { Write-Host "    [skip] $m" -ForegroundColor DarkGray }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Host 'az not found.' -ForegroundColor Red; exit 1 }
try { az account show -o none 2>$null } catch { Write-Host 'Run: az login' -ForegroundColor Red; exit 1 }
if ($LASTEXITCODE -ne 0) { Write-Host 'Run: az login' -ForegroundColor Red; exit 1 }

# Delete order matters: L4 first (SQL failover group on L3), L2 before L1 (firewall in L1 hub).
$order = if ($Level -eq 'All') { @('l4', 'l3', 'l2', 'l1') } else { @($Level.ToLower()) }

Write-Step "Tearing down prefix '$Prefix' — levels: $($order -join ', ')"
foreach ($lvl in $order) {
    $rg = "rg-$Prefix-$lvl"
    $exists = (az group exists --name $rg) -eq 'true'
    if (-not $exists) { Write-Skip "$rg does not exist"; continue }
    if ($PSCmdlet.ShouldProcess($rg, 'Delete resource group')) {
        Write-Host "    deleting $rg ..." -ForegroundColor Yellow
        az group delete --name $rg --yes | Out-Null
        Write-Ok "deleted $rg"
    } else {
        Write-Skip "would delete $rg"
    }
}

if ($RemoveOidc) {
    Write-Step "Removing OIDC identity '$AppName'"
    $appId = az ad app list --display-name $AppName --query '[0].appId' -o tsv 2>$null
    if (-not $appId) {
        Write-Skip "no app named '$AppName'"
    } else {
        $sub = az account show --query id -o tsv
        if ($PSCmdlet.ShouldProcess($appId, 'Remove role assignment + delete app')) {
            az role assignment delete --assignee $appId --scope "/subscriptions/$sub" 2>$null | Out-Null
            az ad app delete --id $appId 2>$null | Out-Null
            Write-Ok "deleted app $appId and its Contributor assignment"
            Write-Host '    NOTE: repo secrets in GitHub are not removed by this script.' -ForegroundColor DarkGray
        } else {
            Write-Skip "would delete app $appId and its role assignment"
        }
    }
}

Write-Host "`nDone." -ForegroundColor Green
if ($WhatIfPreference) { Write-Host 'DRY RUN — nothing was deleted.' -ForegroundColor Yellow }
