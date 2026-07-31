<#
.SYNOPSIS
    Bulk-provisions all student lab environments for one classroom session.

.DESCRIPTION
    For each student account this script:
      1. Creates a resource group  rg-techdemo-<username>  in the target location.
      2. Tags the resource group with Owner, Event, Date and Instructor.
      3. Assigns the student Contributor on their own resource group.
      4. Assigns the instructor Contributor on every resource group.
      5. (Optional) Creates a User Assigned Managed Identity <username>-mi,
         grants it Contributor on the matching resource group, and outputs
         ClientId + PrincipalId so you can verify each identity is unique.

    All steps are idempotent (check-before-act). Re-running is safe.

    ALWAYS preview first with -WhatIf before applying for real.

.PREREQUISITES
    PowerShell 7 with the Az PowerShell module installed:
        Install-Module Az -Scope CurrentUser -Force

    The account running this script requires:
        - Contributor on the subscription (to create resource groups)
        - User Access Administrator or Owner on each resource group
          (to create role assignments — Microsoft.Authorization/roleAssignments/write)
        - Application Administrator in Entra ID only if app registrations are needed
          (not required for this script — UAMI creation does not touch Entra apps)

.PARAMETER SubscriptionId
    Target Azure subscription ID.

.PARAMETER InstructorUpn
    Full UPN of the instructor account (e.g. Saul.Patina@npluslab.onmicrosoft.com).
    This account receives Contributor on every student resource group.

.PARAMETER EventName
    Value written to the 'Event' tag on every resource group. Default: PennConn.

.PARAMETER Location
    Azure region for all resource groups and managed identities. Default: eastus2.

.PARAMETER GitHubOrg
    GitHub organization or username that owns the student repos (optional).
    Used only to print the expected OIDC federated credential subject for reference.

.PARAMETER IncludeManagedIdentity
    When set, also creates a User Assigned Managed Identity (<username>-mi) inside
    each resource group and grants it Contributor on that resource group.

.PARAMETER WhatIf
    Print every planned action without making any changes. Always run this first.

.EXAMPLE
    # Preview all changes
    ./scripts/admin/New-LabEnvironment.ps1 `
        -SubscriptionId "a66afdab-e353-4499-b148-bf42c65b562b" `
        -InstructorUpn "Saul.Patina@npluslab.onmicrosoft.com" `
        -WhatIf

.EXAMPLE
    # Apply for real, include managed identities
    ./scripts/admin/New-LabEnvironment.ps1 `
        -SubscriptionId "a66afdab-e353-4499-b148-bf42c65b562b" `
        -InstructorUpn "Saul.Patina@npluslab.onmicrosoft.com" `
        -IncludeManagedIdentity `
        -GitHubOrg "npluslab"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string] $InstructorUpn,

    [string] $EventName  = 'PennConn',
    [string] $Location   = 'eastus2',
    [string] $GitHubOrg  = '',

    [switch] $IncludeManagedIdentity
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------- #
#  Helpers                                                                      #
# ---------------------------------------------------------------------------- #
function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [ok]   $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg)  { Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Fail($msg)        { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------- #
#  Student roster                                                               #
# ---------------------------------------------------------------------------- #
$StudentUsers = @(
    'Student140801@npluslab.onmicrosoft.com'
    'Student140802@npluslab.onmicrosoft.com'
    'Student140803@npluslab.onmicrosoft.com'
    'Student140804@npluslab.onmicrosoft.com'
    'Student140805@npluslab.onmicrosoft.com'
    'Student140806@npluslab.onmicrosoft.com'
    'Student140807@npluslab.onmicrosoft.com'
    'Student140808@npluslab.onmicrosoft.com'
    'Student140809@npluslab.onmicrosoft.com'
    'Student140810@npluslab.onmicrosoft.com'
    'Student140811@npluslab.onmicrosoft.com'
    'Student140812@npluslab.onmicrosoft.com'
    'Student140813@npluslab.onmicrosoft.com'
    'Student140814@npluslab.onmicrosoft.com'
    'Student140815@npluslab.onmicrosoft.com'
    'Student140816@npluslab.onmicrosoft.com'
    'Student140817@npluslab.onmicrosoft.com'
    'Student140818@npluslab.onmicrosoft.com'
    'Student140819@npluslab.onmicrosoft.com'
    'Student140820@npluslab.onmicrosoft.com'
    'Student140821@npluslab.onmicrosoft.com'
    'Student140822@npluslab.onmicrosoft.com'
    'Student140823@npluslab.onmicrosoft.com'
    'Student140824@npluslab.onmicrosoft.com'
    'Student140825@npluslab.onmicrosoft.com'
    'Student140826@npluslab.onmicrosoft.com'
    'Student140827@npluslab.onmicrosoft.com'
    'Student140828@npluslab.onmicrosoft.com'
    'Student140829@npluslab.onmicrosoft.com'
    'Student140830@npluslab.onmicrosoft.com'
)
# All accounts that get provisioned (students + instructor gets their own RG too)
$AllUsers = @($InstructorUpn) + $StudentUsers

# ---------------------------------------------------------------------------- #
#  Prerequisites                                                                #
# ---------------------------------------------------------------------------- #
Write-Step 'Checking prerequisites'

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Fail 'Az PowerShell module not found. Run: Install-Module Az -Scope CurrentUser -Force'
}
try {
    $ctx = Get-AzContext
    if (-not $ctx -or $ctx.Subscription.Id -ne $SubscriptionId) {
        Write-Warn "Setting subscription context to $SubscriptionId"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
} catch {
    Fail 'Not signed in to Azure. Run: Connect-AzAccount'
}
Write-Ok "Subscription: $SubscriptionId"

$InstructorPrefix = $InstructorUpn.Split('@')[0]
$Today            = (Get-Date -Format 'yyyy-MM-dd')

Write-Ok "Instructor:   $InstructorPrefix"
Write-Ok "Event:        $EventName"
Write-Ok "Date tag:     $Today"
Write-Ok "Location:     $Location"
if ($WhatIfPreference) { Write-Host "`n  *** DRY RUN — no changes will be made ***`n" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------- #
#  Main loop                                                                    #
# ---------------------------------------------------------------------------- #
$Results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($User in $AllUsers) {
    $Prefix = $User.Split('@')[0]
    $RgName = "rg-techdemo-$Prefix"
    $Scope  = "/subscriptions/$SubscriptionId/resourceGroups/$RgName"

    Write-Step "Processing $User  →  $RgName"

    # ── 1. Resource Group ──────────────────────────────────────────────────── #
    $Rg = Get-AzResourceGroup -Name $RgName -ErrorAction SilentlyContinue

    $Tags = @{
        Owner      = $Prefix
        Event      = $EventName
        Date       = $Today
        Instructor = $InstructorPrefix
    }

    if (-not $Rg) {
        if ($PSCmdlet.ShouldProcess($RgName, 'Create resource group')) {
            New-AzResourceGroup -Name $RgName -Location $Location -Tag $Tags | Out-Null
            Write-Ok "Created resource group $RgName"
        } else {
            Write-Skip "Would create resource group $RgName with tags: $($Tags | ConvertTo-Json -Compress)"
        }
    } else {
        # Update tags on existing RG (in case this is a re-run with new tag values)
        if ($PSCmdlet.ShouldProcess($RgName, 'Update resource group tags')) {
            Update-AzTag -ResourceId $Rg.ResourceId -Tag $Tags -Operation Merge | Out-Null
            Write-Skip "Resource group $RgName already exists — tags merged"
        } else {
            Write-Skip "Would merge tags on existing resource group $RgName"
        }
    }

    # ── 2. Student Contributor on their own RG ─────────────────────────────── #
    if ($User -ne $InstructorUpn) {
        $ExistingUserRole = Get-AzRoleAssignment `
            -SignInName $User `
            -RoleDefinitionName Contributor `
            -Scope $Scope `
            -ErrorAction SilentlyContinue

        if (-not $ExistingUserRole) {
            if ($PSCmdlet.ShouldProcess($RgName, "Assign Contributor to $User")) {
                New-AzRoleAssignment `
                    -SignInName $User `
                    -RoleDefinitionName Contributor `
                    -ResourceGroupName $RgName | Out-Null
                Write-Ok "Granted Contributor → $User on $RgName"
            } else {
                Write-Skip "Would grant Contributor → $User on $RgName"
            }
        } else {
            Write-Skip "Contributor for $User already exists on $RgName"
        }
    }

    # ── 3. Instructor Contributor on every RG ─────────────────────────────── #
    if ($User -ne $InstructorUpn) {
        $ExistingInstructorRole = Get-AzRoleAssignment `
            -SignInName $InstructorUpn `
            -RoleDefinitionName Contributor `
            -Scope $Scope `
            -ErrorAction SilentlyContinue

        if (-not $ExistingInstructorRole) {
            if ($PSCmdlet.ShouldProcess($RgName, "Assign Contributor to instructor $InstructorPrefix")) {
                New-AzRoleAssignment `
                    -SignInName $InstructorUpn `
                    -RoleDefinitionName Contributor `
                    -ResourceGroupName $RgName | Out-Null
                Write-Ok "Granted Contributor → $InstructorPrefix (instructor) on $RgName"
            } else {
                Write-Skip "Would grant Contributor → $InstructorPrefix (instructor) on $RgName"
            }
        } else {
            Write-Skip "Instructor Contributor already exists on $RgName"
        }
    }

    # ── 4. User Assigned Managed Identity (optional) ──────────────────────── #
    $MiEntry = $null

    if ($IncludeManagedIdentity) {
        $MiName = "$Prefix-mi"

        $ExistingMi = Get-AzUserAssignedIdentity `
            -ResourceGroupName $RgName `
            -Name $MiName `
            -ErrorAction SilentlyContinue

        if (-not $ExistingMi) {
            if ($PSCmdlet.ShouldProcess("$RgName/$MiName", 'Create User Assigned Managed Identity')) {
                $Mi = New-AzUserAssignedIdentity `
                    -ResourceGroupName $RgName `
                    -Location $Location `
                    -Name $MiName
                Write-Ok "Created UAMI $MiName  (ClientId: $($Mi.ClientId))"
            } else {
                Write-Skip "Would create UAMI $MiName in $RgName"
                $Mi = $null
            }
        } else {
            $Mi = $ExistingMi
            Write-Skip "UAMI $MiName already exists"
        }

        if ($Mi) {
            $ExistingMiRole = Get-AzRoleAssignment `
                -ObjectId $Mi.PrincipalId `
                -RoleDefinitionName Contributor `
                -Scope $Scope `
                -ErrorAction SilentlyContinue

            if (-not $ExistingMiRole) {
                if ($PSCmdlet.ShouldProcess($RgName, "Assign Contributor to UAMI $MiName")) {
                    # Brief retry — MI principal can take seconds to propagate in Entra
                    $Retries = 0
                    do {
                        try {
                            New-AzRoleAssignment `
                                -ObjectId $Mi.PrincipalId `
                                -RoleDefinitionName Contributor `
                                -Scope $Scope | Out-Null
                            $Retries = 99  # exit loop on success
                        } catch {
                            $Retries++
                            if ($Retries -ge 5) { throw }
                            Write-Warn "MI principal not yet propagated — retrying in 10 s ($Retries/5)"
                            Start-Sleep -Seconds 10
                        }
                    } while ($Retries -lt 5)
                    Write-Ok "Granted Contributor → UAMI $MiName on $RgName"
                } else {
                    Write-Skip "Would grant Contributor → UAMI $MiName on $RgName"
                }
            } else {
                Write-Skip "UAMI Contributor role already exists on $RgName"
            }

            $MiEntry = [PSCustomObject]@{
                MIName      = $Mi.Name
                ClientId    = $Mi.ClientId
                PrincipalId = $Mi.PrincipalId
            }
        }
    }

    $Results.Add([PSCustomObject]@{
        User          = $User
        ResourceGroup = $RgName
        MIName        = $MiEntry?.MIName
        ClientId      = $MiEntry?.ClientId
        PrincipalId   = $MiEntry?.PrincipalId
    })
}

# ---------------------------------------------------------------------------- #
#  Summary table                                                                #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Green
Write-Host ' PROVISIONING COMPLETE' -ForegroundColor Green
Write-Host "$('=' * 72)" -ForegroundColor Green

$Results | Format-Table -AutoSize

# ---------------------------------------------------------------------------- #
#  Uniqueness verification (only meaningful when -IncludeManagedIdentity used)  #
# ---------------------------------------------------------------------------- #
if ($IncludeManagedIdentity -and -not $WhatIfPreference) {
    Write-Step 'Verifying UAMI identity uniqueness'

    $AllIdentities = Get-AzUserAssignedIdentity |
        Where-Object { $_.Name -match '^Student\d+-mi$' -or $_.Name -match "^$InstructorPrefix-mi$" }

    $ClientIdDupes = $AllIdentities |
        Group-Object ClientId |
        Where-Object { $_.Count -gt 1 }

    $PrincipalIdDupes = $AllIdentities |
        Group-Object PrincipalId |
        Where-Object { $_.Count -gt 1 }

    if ($ClientIdDupes) {
        Write-Warn "DUPLICATE ClientIds found:"
        $ClientIdDupes | ForEach-Object { Write-Warn "  ClientId $($_.Name) shared by: $($_.Group.Name -join ', ')" }
    } else {
        Write-Ok 'All ClientIds are unique'
    }

    if ($PrincipalIdDupes) {
        Write-Warn "DUPLICATE PrincipalIds found:"
        $PrincipalIdDupes | ForEach-Object { Write-Warn "  PrincipalId $($_.Name) shared by: $($_.Group.Name -join ', ')" }
    } else {
        Write-Ok 'All PrincipalIds are unique'
    }
}

# ---------------------------------------------------------------------------- #
#  OIDC reference — what Setup-Oidc.ps1 will create per student                #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Cyan
Write-Host ' OIDC FEDERATED CREDENTIAL REFERENCE' -ForegroundColor Cyan
Write-Host ' (Setup-Oidc.ps1 creates these automatically when each student runs it)' -ForegroundColor DarkGray
Write-Host "$('=' * 72)" -ForegroundColor Cyan

$OrgSegment = if ($GitHubOrg) { $GitHubOrg } else { '<github-org-or-student-username>' }
Write-Host "`n  Subject format:"
Write-Host "    repo:$OrgSegment/<student-username>:ref:refs/heads/main" -ForegroundColor White
Write-Host "`n  Example for Student140801:"
Write-Host "    repo:$OrgSegment/Student140801:ref:refs/heads/main" -ForegroundColor White
Write-Host "`n  Students run Setup-Oidc.ps1 in Section G of the Start-Here Checklist:"
Write-Host "    ./scripts/Setup-Oidc.ps1 -ResourceGroup rg-techdemo-Student140801 -Prefix Student140801" -ForegroundColor White
Write-Host ''

if ($WhatIfPreference) {
    Write-Host "`n  *** DRY RUN — no changes were made ***" -ForegroundColor Yellow
}
