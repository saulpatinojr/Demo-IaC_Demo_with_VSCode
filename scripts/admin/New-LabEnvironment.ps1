<#
.SYNOPSIS
    Bulk-provisions all student lab environments for one classroom session.

.DESCRIPTION
    Reads the student roster from a CSV file (lab-user-data.csv, located in
    the same folder as this script) and for each row:

      1. Creates a resource group  rg-techdemo-<entra-prefix>  in the target location.
      2. Tags the resource group with four required tags:
             Owner       = Entra UPN prefix of the account (e.g. Student140801)
             Event       = value from the CSV 'Event' column
             Date        = UTC date this script ran (yyyy-MM-dd)
             Instructor  = Entra UPN prefix of the row where Type = Instructor
      3. Assigns the student Contributor on their own resource group.
      4. Assigns the instructor Contributor on every resource group.
      5. (Optional) Creates a User Assigned Managed Identity <prefix>-mi inside
         the resource group, grants it Contributor on that group, and outputs
         ClientId + PrincipalId for uniqueness verification.

    The instructor row (Type = Instructor) is auto-detected from the CSV.
    Use -InstructorUpnOverride to specify a different instructor UPN.

    Expected CSV columns (all required):
        Entra ID Username, TAP, Entra Password, GitHub Username, GH Password, Type, SubscriptionId, Event

    The Type column must contain exactly  Instructor  or  Student.
    SubscriptionId and Event are read from the CSV and must be the same on every row.
    All other columns are read but only Entra ID Username, Type, SubscriptionId, and Event are used.

    All steps are idempotent (check-before-act). Re-running is safe.
    ALWAYS preview first with -WhatIf before applying for real.

.PREREQUISITES
    PowerShell 7 with the Az PowerShell module:
        Install-Module Az -Scope CurrentUser -Force
        Connect-AzAccount

    Permissions required on the running account:
        - Contributor on the subscription (to create resource groups)
        - User Access Administrator or Owner on each resource group
          (Microsoft.Authorization/roleAssignments/write)

.PARAMETER CsvPath
    Path to the lab-user-data.csv file.
    Default: lab-user-data.csv in the same folder as this script.
    SubscriptionId, Event tag, and instructor identity are all read from this file.

.PARAMETER Location
    Azure region for all resource groups and managed identities. Default: eastus2.

.PARAMETER InstructorUpnOverride
    Optional. Override the instructor UPN instead of auto-detecting it from the
    CSV row where Type = Instructor.

.PARAMETER IncludeManagedIdentity
    When set, also creates a User Assigned Managed Identity (<prefix>-mi) inside
    each resource group and grants it Contributor on that group.

.PARAMETER WhatIf
    Print every planned action without making any changes. Always run this first.

.EXAMPLE
    # Preview all changes (reads CSV from default location)
    ./scripts/admin/New-LabEnvironment.ps1 -WhatIf

.EXAMPLE
    # Apply for real, include managed identities
    ./scripts/admin/New-LabEnvironment.ps1 -IncludeManagedIdentity

.EXAMPLE
    # Use a different CSV location
    ./scripts/admin/New-LabEnvironment.ps1 `
        -CsvPath "C:\LabAdmin\session-2\lab-user-data.csv"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $CsvPath                = (Join-Path $PSScriptRoot 'lab-user-data.csv'),
    [string] $Location               = 'eastus2',
    [string] $InstructorUpnOverride  = '',

    [switch] $IncludeManagedIdentity
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------- #
#  Helpers                                                                      #
# ---------------------------------------------------------------------------- #
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok]   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------- #
#  Load and validate the roster CSV                                             #
# ---------------------------------------------------------------------------- #
Write-Step "Loading roster from CSV"

if (-not (Test-Path $CsvPath)) {
    Fail "CSV file not found: $CsvPath`n  Expected: lab-user-data.csv in the same folder as this script."
}

$Roster = Import-Csv -Path $CsvPath |
    Select-Object -Property @{
        # Trim all column values -- the CSV has trailing spaces on many UPNs
        Name       = 'Entra ID Username'
        Expression = { $_.'Entra ID Username'.Trim() }
    }, @{
        Name       = 'GitHubUsername'
        Expression = { $_.'GitHub Username'.Trim() }
    }, @{
        Name       = 'Type'
        Expression = { $_.Type.Trim() }
    }, @{
        Name       = 'SubscriptionId'
        Expression = { $_.SubscriptionId.Trim() }
    }, @{
        Name       = 'Event'
        Expression = { $_.Event.Trim() }
    }

# Validate required columns exist (fail if EITHER key column is missing)
$SampleRow = $Roster | Select-Object -First 1
if ($null -eq $SampleRow.'Entra ID Username' -or $null -eq $SampleRow.Type) {
    Fail "CSV is missing required columns. Expected: 'Entra ID Username', 'GitHub Username', 'Type', 'SubscriptionId', 'Event'"
}

# Extract SubscriptionId from CSV -- validate all rows agree
$SubIds = $Roster | Where-Object { $_.SubscriptionId } |
    Select-Object -ExpandProperty SubscriptionId -Unique

if (-not $SubIds) {
    Fail "No SubscriptionId found in CSV. Add a 'SubscriptionId' column with the target subscription GUID."
}
if ($SubIds.Count -gt 1) {
    Write-Warn "Multiple SubscriptionIds found in CSV: $($SubIds -join ', ')"
    Write-Warn "Using the first value: $($SubIds[0])"
}
$SubscriptionId = $SubIds[0]
Write-Ok "SubscriptionId read from CSV: $SubscriptionId"

# Extract Event from CSV
$EventName = ($Roster | Where-Object { $_.Event } | Select-Object -First 1 -ExpandProperty Event)
if (-not $EventName) {
    Fail "No Event value found in CSV. Add an 'Event' column (e.g. TechConn)."
}
Write-Ok "Event tag read from CSV: $EventName"

# Detect instructor from CSV (Type = Instructor)
$InstructorRow = $Roster | Where-Object { $_.Type -eq 'Instructor' }

if (-not $InstructorRow) {
    if ($InstructorUpnOverride) {
        $InstructorUpn = $InstructorUpnOverride.Trim()
        Write-Warn "No row with Type=Instructor found in CSV. Using -InstructorUpnOverride: $InstructorUpn"
    } else {
        Fail "No row with Type='Instructor' found in CSV and -InstructorUpnOverride not provided."
    }
} else {
    $InstructorUpn = if ($InstructorUpnOverride) { $InstructorUpnOverride.Trim() } `
                     else { $InstructorRow.'Entra ID Username' }
    Write-Ok "Instructor detected: $InstructorUpn"
}

$InstructorPrefix = $InstructorUpn.Split('@')[0]

# All users to provision (instructor gets an RG too)
$AllUsers = $Roster | Where-Object { $_.'Entra ID Username' -ne '' }

Write-Ok "Total accounts in roster: $($AllUsers.Count)"
Write-Ok "  Instructor : $($($Roster | Where-Object { $_.Type -eq 'Instructor' }).Count)"
Write-Ok "  Students   : $($($Roster | Where-Object { $_.Type -eq 'Student' }).Count)"

# ---------------------------------------------------------------------------- #
#  Prerequisites                                                                #
# ---------------------------------------------------------------------------- #
Write-Step 'Checking prerequisites'

# Verify required Az PowerShell modules are installed
foreach ($ModuleName in 'Az.Accounts', 'Az.Resources', 'Az.Authorization') {
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Fail "Required module '$ModuleName' not found.`n  Run: Install-Module Az -Scope CurrentUser -Force"
    }
}
if ($IncludeManagedIdentity -and -not (Get-Module -ListAvailable -Name Az.ManagedServiceIdentity)) {
    Fail "Module 'Az.ManagedServiceIdentity' is required for -IncludeManagedIdentity.`n  Run: Install-Module Az -Scope CurrentUser -Force"
}

# Check Azure sign-in and subscription context
$ctx = Get-AzContext
if (-not $ctx) {
    Fail 'Not signed in to Azure. Run: Connect-AzAccount'
}
if (-not $ctx.Subscription) {
    Fail 'Azure context has no subscription selected. Run: Connect-AzAccount, then Set-AzContext -SubscriptionId <id>'
}
if ($ctx.Subscription.Id -ne $SubscriptionId) {
    Write-Warn "Active subscription ($($ctx.Subscription.Id)) differs from CSV ($SubscriptionId). Switching..."
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        Write-Ok "Switched to subscription $SubscriptionId"
    } catch {
        Fail "Cannot switch to subscription '$SubscriptionId'. Verify the ID in the CSV and that your account has access.`n  $($_.Exception.Message)"
    }
}

$Today = (Get-Date -Format 'yyyy-MM-dd')

Write-Ok "Subscription: $SubscriptionId"
Write-Ok "Instructor:   $InstructorPrefix"
Write-Ok "Event tag:    $EventName (from CSV)"
Write-Ok "Date tag:     $Today"
Write-Ok "Location:     $Location"
if ($WhatIfPreference) { Write-Host "`n  *** DRY RUN -- no changes will be made ***`n" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------- #
#  Main loop                                                                    #
# ---------------------------------------------------------------------------- #
$Results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($Row in $AllUsers) {
    $UserUpn  = $Row.'Entra ID Username'
    $Prefix   = $UserUpn.Split('@')[0]
    $RgName   = "rg-techdemo-$Prefix"
    $Scope    = "/subscriptions/$SubscriptionId/resourceGroups/$RgName"
    $IsStudent = ($Row.Type -eq 'Student')

    Write-Step "[$($Row.Type)] $UserUpn  ->  $RgName"

    # -- 1. Resource Group ---------------------------------------------------- #
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
            Write-Skip "Would create: $RgName  tags=$($Tags | ConvertTo-Json -Compress)"
        }
    } else {
        if ($PSCmdlet.ShouldProcess($RgName, 'Merge tags on existing resource group')) {
            Update-AzTag -ResourceId $Rg.ResourceId -Tag $Tags -Operation Merge | Out-Null
            Write-Skip "$RgName already exists -- tags merged"
        } else {
            Write-Skip "Would merge tags on existing: $RgName"
        }
    }

    # -- 2. Student Contributor on their own RG ------------------------------- #
    if ($IsStudent) {
        $ExistingUserRole = Get-AzRoleAssignment `
            -SignInName $UserUpn `
            -RoleDefinitionName Contributor `
            -Scope $Scope `
            -ErrorAction SilentlyContinue

        if (-not $ExistingUserRole) {
            if ($PSCmdlet.ShouldProcess($RgName, "Assign Contributor -> $Prefix")) {
                $Assigned = $false
                for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
                    try {
                        New-AzRoleAssignment `
                            -SignInName $UserUpn `
                            -RoleDefinitionName Contributor `
                            -ResourceGroupName $RgName `
                            -ErrorAction Stop | Out-Null
                        $Assigned = $true
                        break
                    } catch {
                        if ($Attempt -lt 5) {
                            Write-Warn "[$Prefix] Role assign attempt $Attempt/5 failed -- Entra propagation lag. Retrying in 10 s..."
                            Start-Sleep -Seconds 10
                        }
                    }
                }
                if ($Assigned) { Write-Ok "Granted Contributor -> $Prefix on $RgName" }
                else { Write-Warn "FAILED to assign Contributor -> $Prefix on $RgName after 5 attempts. Re-run the script to retry." }
            } else {
                Write-Skip "Would grant Contributor -> $Prefix on $RgName"
            }
        } else {
            Write-Skip "Contributor for $Prefix already exists on $RgName"
        }
    }

    # -- 3. Instructor Contributor on every RG ------------------------------- #
    if ($IsStudent) {
        $ExistingInstructorRole = Get-AzRoleAssignment `
            -SignInName $InstructorUpn `
            -RoleDefinitionName Contributor `
            -Scope $Scope `
            -ErrorAction SilentlyContinue

        if (-not $ExistingInstructorRole) {
            if ($PSCmdlet.ShouldProcess($RgName, "Assign Contributor -> instructor $InstructorPrefix")) {
                $Assigned = $false
                for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
                    try {
                        New-AzRoleAssignment `
                            -SignInName $InstructorUpn `
                            -RoleDefinitionName Contributor `
                            -ResourceGroupName $RgName `
                            -ErrorAction Stop | Out-Null
                        $Assigned = $true
                        break
                    } catch {
                        if ($Attempt -lt 5) {
                            Write-Warn "[$InstructorPrefix] Instructor role assign attempt $Attempt/5 failed -- retrying in 10 s..."
                            Start-Sleep -Seconds 10
                        }
                    }
                }
                if ($Assigned) { Write-Ok "Granted Contributor -> $InstructorPrefix (instructor) on $RgName" }
                else { Write-Warn "FAILED to assign Instructor Contributor on $RgName after 5 attempts. Re-run to retry." }
            } else {
                Write-Skip "Would grant Contributor -> $InstructorPrefix (instructor) on $RgName"
            }
        } else {
            Write-Skip "Instructor Contributor already exists on $RgName"
        }
    }

    # -- 4. User Assigned Managed Identity (optional) ------------------------ #
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
                if ($PSCmdlet.ShouldProcess($RgName, "Assign Contributor -> UAMI $MiName")) {
                    $Retries = 0
                    do {
                        try {
                            New-AzRoleAssignment `
                                -ObjectId $Mi.PrincipalId `
                                -RoleDefinitionName Contributor `
                                -Scope $Scope | Out-Null
                            $Retries = 99
                        } catch {
                            $Retries++
                            if ($Retries -ge 5) { throw }
                            Write-Warn "MI principal not yet propagated -- retrying in 10 s ($Retries/5)"
                            Start-Sleep -Seconds 10
                        }
                    } while ($Retries -lt 5)
                    Write-Ok "Granted Contributor -> UAMI $MiName on $RgName"
                } else {
                    Write-Skip "Would grant Contributor -> UAMI $MiName on $RgName"
                }
            } else {
                Write-Skip "UAMI Contributor already exists on $RgName"
            }

            $MiEntry = [PSCustomObject]@{
                MIName      = $Mi.Name
                ClientId    = $Mi.ClientId
                PrincipalId = $Mi.PrincipalId
            }
        }
    }

    $Results.Add([PSCustomObject]@{
        Type          = $Row.Type
        User          = $UserUpn
        ResourceGroup = $RgName
        MIName        = if ($MiEntry) { $MiEntry.MIName }      else { '-' }
        ClientId      = if ($MiEntry) { $MiEntry.ClientId }    else { '-' }
        PrincipalId   = if ($MiEntry) { $MiEntry.PrincipalId } else { '-' }
    })
}

# ---------------------------------------------------------------------------- #
#  Summary table                                                                #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Green
Write-Host ' PROVISIONING SUMMARY' -ForegroundColor Green
Write-Host "$('=' * 72)" -ForegroundColor Green

$Results | Format-Table -AutoSize

# ---------------------------------------------------------------------------- #
#  Uniqueness verification (only meaningful when -IncludeManagedIdentity)      #
# ---------------------------------------------------------------------------- #
if ($IncludeManagedIdentity -and -not $WhatIfPreference) {
    Write-Step 'Verifying UAMI identity uniqueness (scoped to lab resource groups)'

    # Scope the query to only the lab RGs created by this script -- avoids
    # false collisions with identities in unrelated resource groups.
    $LabRgNames = $AllUsers | ForEach-Object {
        "rg-techdemo-$($_.'Entra ID Username'.Split('@')[0])"
    }
    $AllIdentities = $LabRgNames | ForEach-Object {
        Get-AzUserAssignedIdentity -ResourceGroupName $_ -ErrorAction SilentlyContinue
    } | Where-Object { $_ }

    $ClientIdDupes = $AllIdentities | Group-Object ClientId  | Where-Object { $_.Count -gt 1 }
    $PrincipalDupes = $AllIdentities | Group-Object PrincipalId | Where-Object { $_.Count -gt 1 }

    if ($ClientIdDupes) {
        Write-Warn 'DUPLICATE ClientIds detected:'
        $ClientIdDupes | ForEach-Object { Write-Warn "  $($_.Name) -- $($_.Group.Name -join ', ')" }
    } else { Write-Ok 'All ClientIds are unique' }

    if ($PrincipalDupes) {
        Write-Warn 'DUPLICATE PrincipalIds detected:'
        $PrincipalDupes | ForEach-Object { Write-Warn "  $($_.Name) -- $($_.Group.Name -join ', ')" }
    } else { Write-Ok 'All PrincipalIds are unique' }
}

# ---------------------------------------------------------------------------- #
#  OIDC reference -- what Setup-Oidc.ps1 creates per student                   #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Cyan
Write-Host ' OIDC FEDERATED CREDENTIAL REFERENCE' -ForegroundColor Cyan
Write-Host ' (each student runs Setup-Oidc.ps1 in Section G -- output shown for reference)' -ForegroundColor DarkGray
Write-Host "$('=' * 72)" -ForegroundColor Cyan

$SampleStudent = $Roster | Where-Object { $_.Type -eq 'Student' } | Select-Object -First 1
if ($SampleStudent) {
    $SamplePrefix = $SampleStudent.'Entra ID Username'.Split('@')[0]
    Write-Host "`n  Federated credential subject format (two-segment owner/repo path):"
    Write-Host "    repo:$SamplePrefix/Demo-IaC_Demo_with_VSCode:ref:refs/heads/main" -ForegroundColor White
    Write-Host "`n  Student runs Setup-Oidc.ps1 from inside their clone:"
    Write-Host "    ./scripts/Setup-Oidc.ps1 -ResourceGroup rg-techdemo-$SamplePrefix -Prefix $SamplePrefix" -ForegroundColor White
}

Write-Host ''
if ($WhatIfPreference) {
    Write-Host '  *** DRY RUN -- no changes were made ***' -ForegroundColor Yellow
}
