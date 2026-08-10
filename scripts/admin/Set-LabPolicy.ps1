<#
.SYNOPSIS
    Applies Azure Policy guardrails to all student lab resource groups by
    deploying lab-policy.bicep.

.DESCRIPTION
    For every resource group matching the -ResourceGroupPrefix pattern, one
    subscription-scope deployment of lab-policy.bicep assigns six Azure
    Policy assignments:

        1. Allowed locations        -- deployments must target the lab regions
        2. Allowed resource types   -- only the resource types used by L1.1-L1.4
        3. Inherit tag: Owner       -- resources inherit Owner from their RG
        4. Inherit tag: Event       -- resources inherit Event from their RG
        5. Inherit tag: Date        -- resources inherit Date from their RG
        6. Inherit tag: Instructor  -- resources inherit Instructor from their RG

    All assignments are scoped to the individual resource group so they do not
    affect other resource groups in the subscription.

    The assignments -- and the resource-type whitelist -- are declared in
    lab-policy.bicep next to this script, the same tool the students use,
    reviewable in the same pull requests. This wrapper adds the parts a
    template cannot do: reading the class CSV and discovering which resource
    groups match the prefix. ARM PUTs are idempotent, so a re-run converges
    existing assignments instead of skipping them -- an edited whitelist
    actually lands. Run with -WhatIf to preview without applying.

.PREREQUISITES
    PowerShell 7 and Azure CLI, signed in with an account holding
    Resource Policy Contributor or Owner on the target resource groups
    (Microsoft.Authorization/policyAssignments/write). Contributor is not
    enough -- the role's notActions exclude it, which is the same wall the
    L2.4 chapter teaches.

.PARAMETER CsvPath
    Path to the lab-user-data.csv file.
    Default: lab-user-data.csv in the same folder as this script.
    SubscriptionId is read from this file.

.PARAMETER ResourceGroupPrefix
    Prefix used to filter which resource groups receive policy assignments.
    Default: rg-techdemo-

.PARAMETER Location
    The allowed Azure regions. Default: eastus2, westus2.

    BOTH are required. L1.1-L1.3 deploy to the primary region (eastus2), but L1.4
    deploys its failover stack to a secondary region -- westus2, the default of
    the secondaryLocation parameter in curriculum/L1.4-production-platform/main.bicep. Restricting
    this to eastus2 alone makes L1.4 undeployable. If you change the lab regions,
    change them here and in the L1.4 template together.

.PARAMETER WhatIf
    Run the deployment's what-if without making any changes.

.EXAMPLE
    # Preview
    ./scripts/admin/Set-LabPolicy.ps1 -WhatIf

.EXAMPLE
    # Apply
    ./scripts/admin/Set-LabPolicy.ps1

.EXAMPLE
    # Use a different CSV location
    ./scripts/admin/Set-LabPolicy.ps1 -CsvPath "C:\LabAdmin\session-2\lab-user-data.csv"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $CsvPath             = (Join-Path $PSScriptRoot 'lab-user-data.csv'),
    [string] $ResourceGroupPrefix = 'rg-techdemo-',
    [string[]] $Location          = @('eastus2', 'westus2')
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

$TemplateFile = Join-Path $PSScriptRoot 'lab-policy.bicep'
if (-not (Test-Path $TemplateFile)) { Fail "Template not found: $TemplateFile" }

# ---------------------------------------------------------------------------- #
#  Read SubscriptionId from CSV                                                 #
# ---------------------------------------------------------------------------- #
Write-Step "Reading configuration from CSV"

if (-not (Test-Path $CsvPath)) {
    Fail "CSV file not found: $CsvPath`n  Expected: lab-user-data.csv in the same folder as this script."
}

$CsvData = Import-Csv -Path $CsvPath |
    Select-Object -Property @{
        Name = 'SubscriptionId'; Expression = { $_.SubscriptionId.Trim() }
    }, @{
        Name = 'Type'; Expression = { $_.Type.Trim() }
    }

$SubIds = $CsvData | Where-Object { $_.SubscriptionId } |
    Select-Object -ExpandProperty SubscriptionId -Unique

if (-not $SubIds) {
    Fail "No SubscriptionId found in CSV. Add a 'SubscriptionId' column with the target subscription GUID."
}
if ($SubIds.Count -gt 1) {
    Write-Warn "Multiple SubscriptionIds in CSV: $($SubIds -join ', '). Using first: $($SubIds[0])"
}
$SubscriptionId = $SubIds[0]
Write-Ok "SubscriptionId from CSV: $SubscriptionId"

# ---------------------------------------------------------------------------- #
#  Azure CLI context                                                            #
# ---------------------------------------------------------------------------- #
Write-Step 'Checking Azure CLI context'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Fail 'Azure CLI not found. Install it, then run az login.'
}

$ctxSub = az account show --query id -o tsv 2>$null
if (-not $ctxSub) { Fail 'Not signed in to Azure. Run: az login' }

if ($ctxSub -ne $SubscriptionId) {
    Write-Warn "Active subscription ($ctxSub) differs from CSV ($SubscriptionId). Switching..."
    az account set --subscription $SubscriptionId 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "Cannot switch to subscription '$SubscriptionId'. Verify the ID in the CSV." }
    Write-Ok "Switched to subscription $SubscriptionId"
}
Write-Ok "Subscription: $SubscriptionId"

# ---------------------------------------------------------------------------- #
#  Discover the target resource groups                                          #
# ---------------------------------------------------------------------------- #
# The one job the template cannot do: a deployment declares which groups get
# the guardrails, it cannot go looking for them.
Write-Step "Finding resource groups matching prefix '$ResourceGroupPrefix'"

$TargetRGs = @(az group list --query "[?starts_with(name, '$ResourceGroupPrefix')].name" -o tsv 2>$null)

if (-not $TargetRGs -or $TargetRGs.Count -eq 0) {
    Write-Warn "No resource groups found matching '$ResourceGroupPrefix'. Run New-LabEnvironment.ps1 first."
    exit 0
}

Write-Ok "Found $($TargetRGs.Count) matching resource groups"
$TargetRGs | ForEach-Object { Write-Ok "  $_" }

# ---------------------------------------------------------------------------- #
#  Deploy the guardrails                                                        #
# ---------------------------------------------------------------------------- #
# Arrays cross the az CLI boundary as JSON.
$rgJson  = ($TargetRGs | ConvertTo-Json -Compress -AsArray)
$locJson = ($Location  | ConvertTo-Json -Compress -AsArray)

$commonArgs = @(
    '--location', $Location[0]
    '--name', 'lab-policy'
    '--template-file', $TemplateFile
    '--parameters', "resourceGroupNames=$rgJson", "allowedLocations=$locJson"
)

if ($WhatIfPreference) {
    Write-Step 'What-if -- no changes will be made'
    az deployment sub what-if @commonArgs
    if ($LASTEXITCODE -ne 0) { Fail 'what-if failed.' }
    exit 0
}

if (-not $PSCmdlet.ShouldProcess($SubscriptionId, "Assign lab policy guardrails to $($TargetRGs.Count) resource groups")) { exit 0 }

Write-Step 'Deploying policy assignments'
$outputs = az deployment sub create @commonArgs --query 'properties.outputs' -o json
if ($LASTEXITCODE -ne 0) {
    Fail 'Deployment failed. Do you hold Resource Policy Contributor or Owner? Contributor cannot write policy assignments.'
}
$o = $outputs | ConvertFrom-Json

# ---------------------------------------------------------------------------- #
#  Summary                                                                      #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Green
Write-Host " POLICY ASSIGNMENTS COMPLETE" -ForegroundColor Green
Write-Host "$('=' * 72)" -ForegroundColor Green
Write-Host "  Resource groups processed : $($o.resourceGroupsProcessed.value)"
Write-Host "  Assignments per group     : $($o.assignmentsPerGroup.value)  (location + resource types + 4 tags)"
Write-Host "  Allowed locations         : $($Location -join ', ')"
Write-Host "  Resource type whitelist   : $($o.resourceTypeCount.value) types (see lab-policy.bicep)"
Write-Host ''
