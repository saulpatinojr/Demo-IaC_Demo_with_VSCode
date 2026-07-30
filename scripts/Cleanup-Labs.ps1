<#
.SYNOPSIS
    Delete the workshop's Azure resources (and optionally the OIDC identity).

.DESCRIPTION
    The labs create real, billable resources - Azure Firewall, Bastion, Front
    Door and SQL all bill while idle. This script tears them down.

    Classroom mode (-ResourceGroup): deletes ALL resources inside the shared
    resource group without deleting the group itself (students typically don't
    have permission to delete the RG). Resources are deleted in parallel; some
    dependent resources (e.g. Private Endpoints before their parent) may need
    two passes.

    Standard mode: deletes the lab resource groups rg-<prefix>-l1..l4 in the
    correct order (L4 first, L1 last).

    ALWAYS preview first:   ./scripts/Cleanup-Labs.ps1 -WhatIf

.PARAMETER ResourceGroup
    When set, delete all resources INSIDE this group (classroom mode). The
    group itself is not deleted. Ignores -Prefix and -Level.

.PARAMETER Prefix
    Resource-name prefix used when deploying. Default: iacdemo. Resource groups
    are rg-<prefix>-l1 .. rg-<prefix>-l4.

.PARAMETER Level
    Which labs to remove (standard mode only): All (default), L4, L3, L2, L1.

.PARAMETER RemoveOidc
    Also delete the Entra app registration named by -AppName and its role
    assignment. Off by default so you can redeploy without re-running setup.

.PARAMETER AppName
    Entra app to remove when -RemoveOidc is set. Defaults to "iac-demo-<Prefix>"
    to match the name created by Setup-Oidc.ps1.

.PARAMETER WhatIf
    Show what would be deleted without deleting anything.

.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -WhatIf
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-alice"   # classroom mode
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1                                  # delete all lab RGs (standard)
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -Level L2                        # delete only rg-iacdemo-l2
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -RemoveOidc                      # full teardown incl. OIDC identity
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $ResourceGroup,
    [string] $Prefix = 'iacdemo',
    [ValidateSet('All', 'L4', 'L3', 'L2', 'L1')]
    [string] $Level = 'All',
    [switch] $RemoveOidc,
    [string] $AppName = ''
)

$ErrorActionPreference = 'Stop'
function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Write-Skip($m) { Write-Host "    [skip] $m" -ForegroundColor DarkGray }

if (-not $AppName) { $AppName = "iac-demo-$Prefix" }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Host 'az not found.' -ForegroundColor Red; exit 1 }
try { az account show -o none 2>$null } catch { Write-Host 'Run: az login' -ForegroundColor Red; exit 1 }
if ($LASTEXITCODE -ne 0) { Write-Host 'Run: az login' -ForegroundColor Red; exit 1 }

# ---- Classroom mode: delete resources inside a shared RG -------------------
if ($ResourceGroup) {
    Write-Step "Classroom mode: deleting all resources in '$ResourceGroup'"
    $rgExists = (az group exists --name $ResourceGroup) -eq 'true'
    if (-not $rgExists) { Write-Skip "Resource group '$ResourceGroup' not found; nothing to delete"; return }

    $ids = az resource list --resource-group $ResourceGroup --query '[].id' -o tsv 2>$null
    if (-not $ids) { Write-Skip 'No resources found in the resource group'; return }

    $idList = ($ids -split "`n") -replace '\r', '' | Where-Object { $_ }
    Write-Host "    Found $($idList.Count) resource(s) to delete." -ForegroundColor Yellow

    if ($PSCmdlet.ShouldProcess($ResourceGroup, "Delete $($idList.Count) resources")) {
        # Delete in one batch; ARM handles dependency ordering within the group.
        az resource delete --ids $idList | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "All resources deleted from '$ResourceGroup'"
        } else {
            Write-Host '    Some resources may not have deleted (dependency ordering). Re-run to clean up.' -ForegroundColor Yellow
        }
    } else {
        $idList | ForEach-Object { Write-Skip "would delete $_" }
    }
    Write-Host "`nDone." -ForegroundColor Green
    if ($WhatIfPreference) { Write-Host 'DRY RUN - nothing was deleted.' -ForegroundColor Yellow }
    return
}

# ---- Standard mode: delete whole lab resource groups -----------------------
# Delete order matters: L4 first (SQL failover group on L3), L2 before L1 (firewall in L1 hub).
$order = if ($Level -eq 'All') { @('l4', 'l3', 'l2', 'l1') } else { @($Level.ToLower()) }

Write-Step "Tearing down prefix '$Prefix' - levels: $($order -join ', ')"
foreach ($lvl in $order) {
    $rg = "rg-$Prefix-$lvl"
    $exists = (az group exists --name $rg) -eq 'true'
    if (-not $exists) { Write-Skip "$rg does not exist; nothing to delete"; continue }
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
if ($WhatIfPreference) { Write-Host 'DRY RUN - nothing was deleted.' -ForegroundColor Yellow }
