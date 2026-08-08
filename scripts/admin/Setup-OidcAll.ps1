<#
.SYNOPSIS
    Instructor-run bulk OIDC setup -- wires up GitHub ↔ Azure for all students at once.

.DESCRIPTION
    Reads lab-user-data.csv and for every Student row:

      1. Creates (or reuses) an Entra app registration named  iac-demo-<prefix>
      2. Creates (or reuses) a service principal for that app
      3. Adds federated credentials so GitHub Actions on the student's fork can
         authenticate to Azure with no stored secret -- one for the main branch,
         one for pull requests
      4. Grants the service principal  Contributor  on the student's resource group
         rg-techdemo-<prefix>  (which must already exist -- run New-LabEnvironment.ps1 first)
      5. Pushes the following to the student's GitHub fork as secrets / variables:
             Secrets  : AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID,
                        AZURE_RESOURCE_GROUP, VM_ADMIN_PASSWORD, SQL_ADMIN_PASSWORD
             Variables: AZURE_PREFIX, AZURE_LOCATION

    When this script completes, students can skip straight to  Section G -> Step 3 (Verify)
    in the Start-Here Checklist.  gh secret list  on their fork will already show
    all six secrets.

    GitHub handle derivation:
        Student GitHub username is assumed to be the Entra UPN prefix
        (e.g.  Student140801@npluslab.onmicrosoft.com  ->  Student140801).
        The fork repo is:  <derived-handle>/Demo-IaC_Demo_with_VSCode
        Override the repo name with -RepoName if needed.

    PREREQUISITES:
        - Azure CLI (az)  signed in with  az login
        - GitHub CLI (gh) signed in with  gh auth login
          The gh account must have  Admin  access on every student's fork
          (org admin in a shared org, or individual collaborator rights).
        - Run New-LabEnvironment.ps1 first -- the resource groups must exist.

    All steps are idempotent. Re-running repairs any missing piece.
    ALWAYS use -WhatIf first to preview every action.

.PARAMETER CsvPath
    Path to lab-user-data.csv. Default: same folder as this script.

.PARAMETER Location
    AZURE_LOCATION variable value pushed to each student's fork. Default: eastus2.

.PARAMETER RepoName
    GitHub repository name (not the full path -- just the repo name).
    Default: auto-detected from the current git remote, fallback to
    Demo-IaC_Demo_with_VSCode.

.PARAMETER Branch
    Branch name used in the federated credential subject. Default: main.

.PARAMETER WhatIf
    Print every planned action without making any changes.

.EXAMPLE
    # Preview
    ./scripts/admin/Setup-OidcAll.ps1 -WhatIf

.EXAMPLE
    # Apply for real
    ./scripts/admin/Setup-OidcAll.ps1

.EXAMPLE
    # Different CSV location or repo name
    ./scripts/admin/Setup-OidcAll.ps1 `
        -CsvPath "C:\LabAdmin\session-2\lab-user-data.csv" `
        -RepoName "Demo-IaC_Demo_with_VSCode"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $CsvPath  = (Join-Path $PSScriptRoot 'lab-user-data.csv'),
    [string] $Location = 'eastus2',
    [string] $RepoName = '',
    [string] $Branch   = 'main'
)

$ErrorActionPreference = 'Stop'
$issuer   = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'

# ---------------------------------------------------------------------------- #
#  Helpers                                                                      #
# ---------------------------------------------------------------------------- #
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok]   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

function New-ThrowawayPassword {
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; $lower = 'abcdefghijkmnpqrstuvwxyz'
    $num   = '23456789';                $sym   = '!@#$%^*-_'
    $all   = "$upper$lower$num$sym".ToCharArray()
    $pw    = ($upper[(Get-Random -Max $upper.Length)]) + ($lower[(Get-Random -Max $lower.Length)]) +
             ($num[(Get-Random -Max $num.Length)])     + ($sym[(Get-Random -Max $sym.Length)])
    1..16 | ForEach-Object { $pw += $all[(Get-Random -Max $all.Length)] }
    return $pw
}

# ---------------------------------------------------------------------------- #
#  Load CSV                                                                     #
# ---------------------------------------------------------------------------- #
Write-Step 'Loading roster from CSV'

if (-not (Test-Path $CsvPath)) {
    Fail "CSV not found: $CsvPath"
}

$Roster = Import-Csv -Path $CsvPath | ForEach-Object {
    [PSCustomObject]@{
        Upn            = $_.'Entra ID Username'.Trim()
        GitHubUsername = $_.'GitHub Username'.Trim()
        Type           = $_.Type.Trim()
        SubscriptionId = $_.SubscriptionId.Trim()
        Event          = $_.Event.Trim()
    }
}

# Extract shared config values (same on every row)
$SubscriptionId = ($Roster | Where-Object { $_.SubscriptionId } | Select-Object -First 1).SubscriptionId
$TenantId       = $null   # resolved below after az login check

if (-not $SubscriptionId) {
    Fail "No SubscriptionId in CSV. Add a 'SubscriptionId' column."
}

$InstructorRow = ($Roster | Where-Object { $_.Type -eq 'Instructor' } | Select-Object -First 1)
if (-not $InstructorRow) { Fail "No row with Type='Instructor' found in CSV." }
if (($Roster | Where-Object { $_.Type -eq 'Instructor' }).Count -gt 1) {
    Write-Warn "Multiple Instructor rows found in CSV. Using first: $($InstructorRow.Upn)"
}
$InstructorUpn    = $InstructorRow.Upn
$InstructorPrefix = $InstructorUpn.Split('@')[0]

$Students = $Roster | Where-Object { $_.Type -eq 'Student' -and $_.Upn }
Write-Ok "Instructor : $InstructorUpn"
Write-Ok "Students   : $($Students.Count)"
Write-Ok "Subscription: $SubscriptionId"

# ---------------------------------------------------------------------------- #
#  Auto-detect repo name if not provided                                        #
# ---------------------------------------------------------------------------- #
if (-not $RepoName) {
    $RemoteUrl = git remote get-url origin 2>$null
    if ($RemoteUrl -match '[/:]([^/]+)\.git$') {
        $RepoName = $Matches[1]
    } elseif ($RemoteUrl -match '[/:]([^/]+)$') {
        $RepoName = $Matches[1]
    } else {
        $RepoName = 'Demo-IaC_Demo_with_VSCode'
        Write-Warn "Could not detect repo name from git remote. Using default: $RepoName"
    }
}
Write-Ok "Repo name  : $RepoName"

# ---------------------------------------------------------------------------- #
#  Prerequisite checks                                                          #
# ---------------------------------------------------------------------------- #
Write-Step 'Checking prerequisites'

foreach ($Tool in 'az', 'gh') {
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        Fail "$Tool CLI not found. Install it and re-run. See Start-Here Checklist Section C."
    }
}

# Azure CLI auth -- external process: check exit code, NOT try/catch
az account show -o none 2>$null
if ($LASTEXITCODE -ne 0) { Fail 'Not signed in to Azure. Run: az login' }

# Set subscription context and verify it worked
az account set --subscription $SubscriptionId 2>$null
if ($LASTEXITCODE -ne 0) {
    Fail "Cannot switch to subscription '$SubscriptionId'.`n  Verify the SubscriptionId in the CSV and that you have access to it."
}

$TenantId = az account show --query tenantId -o tsv
if (-not $TenantId) { Fail 'Could not retrieve TenantId. Check Azure sign-in and subscription access.' }

# GitHub CLI auth
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'Not signed in to GitHub. Run: gh auth login' }

Write-Ok "az  -- signed in. TenantId: $TenantId  Subscription: $SubscriptionId"
Write-Ok "gh  -- signed in."

if ($WhatIfPreference) { Write-Host "`n  *** DRY RUN -- no changes will be made ***`n" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------- #
#  Helper functions (defined once at script scope -- not inside the loop)       #
# ---------------------------------------------------------------------------- #
function Ensure-FedCred($Name, $Subject, $AppId) {
    $Existing = az ad app federated-credential list --id $AppId `
        --query "[?subject=='$Subject'] | [0].name" -o tsv 2>$null
    if ($Existing) { Write-Skip "Federated cred '$Name' already exists"; return }
    if ($PSCmdlet.ShouldProcess($Subject, "Create federated credential '$Name'")) {
        $Params = @{ name = $Name; issuer = $issuer; subject = $Subject; audiences = @($audience) } |
            ConvertTo-Json -Compress
        $Tmp = New-TemporaryFile
        Set-Content -Path $Tmp -Value $Params -Encoding utf8
        az ad app federated-credential create --id $AppId --parameters "@$Tmp" | Out-Null
        Remove-Item $Tmp -Force
        Write-Ok "Created federated credential '$Name'"
    } else { Write-Skip "Would create federated credential '$Name' for $Subject" }
}

function Set-RepoSecret($ForkRepo, $Name, $Value) {
    if ($PSCmdlet.ShouldProcess("$ForkRepo secret $Name", 'Set')) {
        # `gh secret set` reads stdin ONLY when --body is absent; `--body -`
        # stores the literal string "-" and every deploy then fails to log in.
        $Value | gh secret set $Name --repo $ForkRepo 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not set secret $Name on $ForkRepo`n  Check that your gh account has Admin access to this fork."
        } else { Write-Ok "Secret set: $Name" }
    } else { Write-Skip "Would set secret $Name on $ForkRepo" }
}

function Set-RepoVariable($ForkRepo, $Name, $Value) {
    if ($PSCmdlet.ShouldProcess("$ForkRepo variable $Name", 'Set')) {
        gh variable set $Name --repo $ForkRepo --body $Value 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not set variable $Name on $ForkRepo`n  Check that your gh account has Admin access to this fork."
        } else { Write-Ok "Variable set: $Name = $Value" }
    } else { Write-Skip "Would set variable $Name = $Value on $ForkRepo" }
}

# ---------------------------------------------------------------------------- #
#  Per-student OIDC setup                                                       #
# ---------------------------------------------------------------------------- #
$Results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($Student in $Students) {
    $Prefix        = $Student.Upn.Split('@')[0]
    $AppName       = "iac-demo-$Prefix"
    $RgName        = "rg-techdemo-$Prefix"
    $Scope         = "/subscriptions/$SubscriptionId/resourceGroups/$RgName"
    # Derive GitHub handle: UPN prefix (e.g. Student140801)
    $GitHubHandle  = $Prefix
    $ForkRepo      = "$GitHubHandle/$RepoName"
    $SubjectMain   = "repo:${ForkRepo}:ref:refs/heads/$Branch"
    $SubjectPR     = "repo:${ForkRepo}:pull_request"

    Write-Step "[$Prefix]  fork: $ForkRepo  rg: $RgName"

    # Verify the RG exists
    $RgExists = az group show --name $RgName --query name -o tsv 2>$null
    if (-not $RgExists) {
        Write-Warn "Resource group '$RgName' not found. Run New-LabEnvironment.ps1 first. Skipping $Prefix."
        continue
    }

    # -- App registration --------------------------------------------------- #
    # Query all apps with this display name -- warn if multiple found (collision risk)
    $AppIds = @(az ad app list --display-name $AppName --query '[].appId' -o tsv 2>$null |
        Where-Object { $_.Trim() })
    if ($AppIds.Count -gt 1) {
        Write-Warn "Multiple Entra apps found with display name '$AppName' -- using first. Clean up duplicates in Entra ID."
    }
    $AppId = if ($AppIds.Count -ge 1) { $AppIds[0].Trim() } else { $null }

    if (-not $AppId) {
        if ($PSCmdlet.ShouldProcess($AppName, 'Create Entra app registration')) {
            $AppId = az ad app create --display-name $AppName --query appId -o tsv
            if (-not $AppId) {
                Write-Warn "Could not create Entra app '$AppName' -- skipping this student. Check your directory permissions."
                continue
            }
            $AppId = $AppId.Trim()
            Write-Ok "Created app: $AppName  ($AppId)"
        } else { Write-Skip "Would create app: $AppName"; $AppId = '<new-app-id>' }
    } else { Write-Skip "App exists: $AppName  ($AppId)" }

    # -- Service principal -------------------------------------------------- #
    # az prints nothing when the JMESPath result is null, so the capture is
    # $null and .Trim() on it would terminate the whole roster run -- which is
    # exactly the fresh-provisioning case this script exists for.
    $SpId = az ad sp list --filter "appId eq '$AppId'" --query '[0].id' -o tsv 2>$null
    if ($SpId) { $SpId = $SpId.Trim() }
    if (-not $SpId) {
        if ($PSCmdlet.ShouldProcess($AppId, 'Create service principal')) {
            az ad sp create --id $AppId | Out-Null
            Write-Ok "Created service principal for $AppName"
        } else { Write-Skip "Would create service principal for $AppName" }
    } else { Write-Skip "Service principal exists for $AppName" }

    # -- Federated credentials ---------------------------------------------- #
    Ensure-FedCred "gh-$Branch-$Prefix" $SubjectMain $AppId
    Ensure-FedCred "gh-pr-$Prefix"      $SubjectPR   $AppId

    # -- Contributor on student's RG ---------------------------------------- #
    $HasRole = az role assignment list --assignee $AppId --scope $Scope `
        --role Contributor --query '[0].id' -o tsv 2>$null
    if ($HasRole) { $HasRole = $HasRole.Trim() }
    if ($HasRole) {
        Write-Skip "Contributor already assigned on $RgName"
    } elseif ($PSCmdlet.ShouldProcess($Scope, "Assign Contributor to $AppName")) {
        for ($i = 1; $i -le 5; $i++) {
            az role assignment create --assignee $AppId --role Contributor --scope $Scope 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Seconds 6
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Role assignment failed for $AppName -- SP may still be propagating. Re-run to retry."
        } else { Write-Ok "Assigned Contributor on $RgName" }
    } else { Write-Skip "Would assign Contributor on $RgName" }

    # -- Derive AZURE_PREFIX (must be ≤12 chars for Bicep @maxLength(12)) --- #
    # Pattern: 'Student140801' -> 'stu140801' (9 chars).  Generic fallback:
    # strip non-alphanumeric, lowercase, truncate to 12.
    if ($Prefix -match '^Student(\d+)$') {
        $AzurePrefix = 'stu' + $Matches[1]
        if ($AzurePrefix.Length -gt 12) { $AzurePrefix = $AzurePrefix.Substring(0, 12) }
    } else {
        $AzurePrefix = ($Prefix -replace '[^a-zA-Z0-9]', '').ToLower()
        if ($AzurePrefix.Length -gt 12) {
            $AzurePrefix = $AzurePrefix.Substring(0, 12)
            Write-Warn "Prefix '$Prefix' truncated to '$AzurePrefix' for AZURE_PREFIX (Bicep @maxLength(12))"
        }
    }
    Write-Ok "AZURE_PREFIX: $AzurePrefix  (derived from UPN prefix '$Prefix')"

    # -- GitHub secrets & variables ----------------------------------------- #
    $VmPwd  = New-ThrowawayPassword
    $SqlPwd = New-ThrowawayPassword

    Set-RepoSecret  $ForkRepo 'AZURE_CLIENT_ID'       $AppId
    Set-RepoSecret  $ForkRepo 'AZURE_TENANT_ID'       $TenantId
    Set-RepoSecret  $ForkRepo 'AZURE_SUBSCRIPTION_ID' $SubscriptionId
    Set-RepoSecret  $ForkRepo 'AZURE_RESOURCE_GROUP'  $RgName
    Set-RepoSecret  $ForkRepo 'VM_ADMIN_PASSWORD'     $VmPwd
    Set-RepoSecret  $ForkRepo 'SQL_ADMIN_PASSWORD'    $SqlPwd
    Set-RepoVariable $ForkRepo 'AZURE_PREFIX'          $AzurePrefix
    Set-RepoVariable $ForkRepo 'AZURE_LOCATION'        $Location

    $Results.Add([PSCustomObject]@{
        Student       = $Prefix
        AzurePrefix   = $AzurePrefix
        App           = $AppName
        AppId         = $AppId
        ResourceGroup = $RgName
        ForkRepo      = $ForkRepo
        Status        = 'Done'
    })
}

# ---------------------------------------------------------------------------- #
#  Summary                                                                      #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Green
Write-Host ' OIDC SETUP SUMMARY' -ForegroundColor Green
Write-Host "$('=' * 72)" -ForegroundColor Green

$Results | Format-Table -AutoSize

Write-Host ''
if ($WhatIfPreference) {
    Write-Host '  *** DRY RUN -- no changes were made ***' -ForegroundColor Yellow
} else {
    Write-Host '  Students can now skip to Section G -> Step 3 (Verify)' -ForegroundColor Green
    Write-Host "  gh secret list  on each fork should show 6 secrets." -ForegroundColor Green
}
Write-Host ''
