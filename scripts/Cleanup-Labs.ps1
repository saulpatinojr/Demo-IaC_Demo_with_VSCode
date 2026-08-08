<#
.SYNOPSIS
    Delete the workshop's Azure resources (and optionally the OIDC identity).

.DESCRIPTION
    The labs create real, billable resources - Azure Firewall, Bastion, Front
    Door and SQL all bill while idle. This script tears them down.

    All four labs deploy into ONE resource group (the one Setup-Oidc.ps1 stored
    as the AZURE_RESOURCE_GROUP secret), so that group is the unit of teardown.
    This script deletes every resource inside the group but leaves the group
    itself in place, because classroom students usually hold Contributor on the
    group only and cannot delete it.

    ALWAYS preview first:
        ./scripts/Cleanup-Labs.ps1 -ResourceGroup "<your rg>" -WhatIf

.PARAMETER ResourceGroup
    The resource group the labs deployed into. Falls back to the
    AZURE_RESOURCE_GROUP environment variable when not supplied.

.PARAMETER Prefix
    Resource-name prefix used when deploying. Default: iacdemo. Only used to
    derive the default -AppName for -RemoveOidc.

.PARAMETER RemoveOidc
    Also delete the Entra app registration named by -AppName and every role
    assignment it holds. Off by default so you can redeploy without re-running
    setup.

.PARAMETER AppName
    Entra app to remove when -RemoveOidc is set. Defaults to "iac-demo-<Prefix>"
    to match the name created by Setup-Oidc.ps1.

.PARAMETER WhatIf
    Show what would be deleted without deleting anything.

.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -ResourceGroup "rg-lab-alice" -WhatIf
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP
.EXAMPLE
    ./scripts/Cleanup-Labs.ps1 -Prefix "alice" -RemoveOidc   # identity only
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $ResourceGroup,
    [string] $Prefix = 'iacdemo',
    [switch] $RemoveOidc,
    [string] $AppName = ''
)

$ErrorActionPreference = 'Stop'
# az returns non-zero for expected conditions and writes progress to stderr.
# Keep PowerShell 7.4+ from turning those into terminating errors so the
# explicit $LASTEXITCODE checks below are the single source of truth.
$PSNativeCommandUseErrorActionPreference = $false

function Write-Banner($text) {
    $line = '=' * ($text.Length + 8)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host "  === $text ===" -ForegroundColor Yellow
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host ""
}
function Write-Step($m) { Write-Host ""; Write-Host "  > $m" -ForegroundColor White }
function Write-Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Skip($m) { Write-Host "    [SKIP] $m" -ForegroundColor DarkGray }
function Write-Warn($m) { Write-Host "    [WARN] $m" -ForegroundColor Yellow }
function Write-Fail($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }

if (-not $AppName) { $AppName = "iac-demo-$Prefix" }

Write-Banner 'Lab Cleanup'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Fail 'az not found.'; exit 1 }
try { az account show -o none 2>$null } catch { Write-Fail 'Run: az login'; exit 1 }
if ($LASTEXITCODE -ne 0) { Write-Fail 'Run: az login'; exit 1 }

# ---- Work out which resource group to empty --------------------------------
if (-not $ResourceGroup -and $env:AZURE_RESOURCE_GROUP) {
    $ResourceGroup = $env:AZURE_RESOURCE_GROUP
    Write-Skip "using AZURE_RESOURCE_GROUP from the environment: $ResourceGroup"
}

if (-not $ResourceGroup) {
    if ($RemoveOidc) {
        Write-Warn 'No resource group given - removing the OIDC identity only.'
        Write-Warn 'Lab resources (firewall, Bastion, SQL) are still deployed and still billing.'
    } else {
        Write-Fail 'No resource group to clean up.'
        Write-Host '    Pass -ResourceGroup "<your lab rg>", or run ./scripts/Load-LabSettings.ps1' -ForegroundColor DarkGray
        Write-Host '    first so AZURE_RESOURCE_GROUP is set. All four labs share one group.' -ForegroundColor DarkGray
        exit 1
    }
}

# ---- Delete everything inside the group ------------------------------------
if ($ResourceGroup) {
    Write-Step "Deleting all resources in '$ResourceGroup'"

    $rgExists = (az group exists --name $ResourceGroup) -eq 'true'
    if (-not $rgExists) {
        Write-Fail "Resource group '$ResourceGroup' not found - nothing was deleted."
        Write-Host '    Check the name against your AZURE_RESOURCE_GROUP secret.' -ForegroundColor DarkGray
        if (-not $RemoveOidc) { exit 1 }
    } else {
        # Private DNS virtual-network links are CHILD resources: `az resource
        # list` never returns them, and a zone refuses to delete while a link
        # survives. Without this the L3 privatelink zones outlive every pass.
        $zones = @(az network private-dns zone list --resource-group $ResourceGroup --query '[].name' -o tsv 2>$null | Where-Object { $_ })
        foreach ($zone in $zones) {
            $links = @(az network private-dns link vnet list --resource-group $ResourceGroup --zone-name $zone --query '[].name' -o tsv 2>$null | Where-Object { $_ })
            foreach ($link in $links) {
                if ($PSCmdlet.ShouldProcess("$zone/$link", 'Delete private DNS vnet link')) {
                    az network private-dns link vnet delete --resource-group $ResourceGroup --zone-name $zone --name $link --yes 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Ok "removed DNS link $zone/$link" }
                    else { Write-Warn "could not remove DNS link $zone/$link" }
                } else {
                    Write-Skip "would remove DNS link $zone/$link"
                }
            }
        }

        # Several passes: ARM rejects a delete while a dependent resource still
        # references the target (private endpoints before their parent, the
        # firewall before its public IP, and so on).
        $remaining = @()
        $declined  = $false
        for ($pass = 1; $pass -le 3; $pass++) {
            $ids = @(az resource list --resource-group $ResourceGroup --query '[].id' -o tsv 2>$null | Where-Object { $_ })
            if ($LASTEXITCODE -ne 0) {
                Write-Fail "Could not list resources in '$ResourceGroup' - check your permissions."
                exit 1
            }

            $remaining = $ids
            if ($ids.Count -eq 0) {
                Write-Ok "'$ResourceGroup' contains no resources"
                break
            }

            if (-not $PSCmdlet.ShouldProcess($ResourceGroup, "Delete $($ids.Count) resources")) {
                $ids | ForEach-Object { Write-Skip "would delete $_" }
                $declined = $true
                break
            }

            Write-Warn "Pass $pass - deleting $($ids.Count) resource(s) ..."
            az resource delete --ids $ids 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "pass $pass completed"
            } else {
                Write-Warn "pass $pass left some resources behind (dependency ordering)"
            }
        }

        # Only a real delete attempt can leave something "surviving" - a dry run
        # or a declined confirmation prompt has simply not tried yet.
        if (-not $WhatIfPreference -and -not $declined -and $remaining.Count -gt 0) {
            $left = @(az resource list --resource-group $ResourceGroup --query '[].id' -o tsv 2>$null | Where-Object { $_ })
            if ($left.Count -gt 0) {
                Write-Fail "$($left.Count) resource(s) survived all 3 passes and are STILL BILLING:"
                $left | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
                Write-Host '    Re-run this script, or delete them in the Azure portal.' -ForegroundColor DarkGray
                exit 1
            }
            Write-Ok "'$ResourceGroup' is now empty"
        }
    }
}

# ---- Optionally remove the OIDC identity -----------------------------------
if ($RemoveOidc) {
    Write-Step "Removing OIDC identity '$AppName'"
    $appId = az ad app list --display-name $AppName --query '[0].appId' -o tsv 2>$null
    if ($appId) { $appId = $appId.Trim() }
    if (-not $appId) {
        Write-Skip "no app named '$AppName'"
    } else {
        if ($PSCmdlet.ShouldProcess($appId, 'Remove role assignments + delete app')) {
            # Setup-Oidc.ps1 grants Contributor at RESOURCE GROUP scope, so a
            # subscription-scoped delete matches nothing and silently leaves an
            # orphaned assignment. List what the app actually holds instead.
            $assignments = @(az role assignment list --assignee $appId --all --query '[].id' -o tsv 2>$null | Where-Object { $_ })
            if ($assignments.Count -gt 0) {
                az role assignment delete --ids $assignments 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Ok "removed $($assignments.Count) role assignment(s)" }
                else { Write-Warn 'some role assignments could not be removed' }
            } else {
                Write-Skip 'no role assignments found for this app'
            }

            az ad app delete --id $appId 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Ok "deleted app $appId" }
            else { Write-Fail "could not delete app $appId" }
            Write-Host '    NOTE: repo secrets in GitHub are not removed by this script.' -ForegroundColor DarkGray
        } else {
            Write-Skip "would delete app $appId and its role assignments"
        }
    }
}

Write-Ok 'Done.'
if ($WhatIfPreference) { Write-Warn 'DRY RUN - nothing was deleted.' }
