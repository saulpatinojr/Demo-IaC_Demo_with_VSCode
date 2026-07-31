<#
.SYNOPSIS
    Applies Azure Policy guardrails to all student lab resource groups.

.DESCRIPTION
    For every resource group matching the -ResourceGroupPrefix pattern this
    script assigns six Azure Policy assignments:

        1. Allowed locations        -- deployments must target eastus2 only
        2. Allowed resource types   -- only the resource types used by L1-L4
        3. Inherit tag: Owner       -- resources inherit Owner from their RG
        4. Inherit tag: Event       -- resources inherit Event from their RG
        5. Inherit tag: Date        -- resources inherit Date from their RG
        6. Inherit tag: Instructor  -- resources inherit Instructor from their RG

    All assignments are scoped to the individual resource group so they do not
    affect other resource groups in the subscription.

    All assignments are idempotent (existing assignments with the same name are
    left in place). Run with -WhatIf to preview without applying.

.PREREQUISITES
    PowerShell 7 with the Az PowerShell module installed:
        Install-Module Az -Scope CurrentUser -Force

    The account running this script requires:
        - Resource Policy Contributor or Owner on each target resource group
          (Microsoft.Authorization/policyAssignments/write)

.PARAMETER CsvPath
    Path to the lab-user-data.csv file.
    Default: lab-user-data.csv in the same folder as this script.
    SubscriptionId and ResourceGroupPrefix pattern are read from this file.

.PARAMETER ResourceGroupPrefix
    Prefix used to filter which resource groups receive policy assignments.
    Default: rg-techdemo-

.PARAMETER Location
    The single allowed Azure region. Default: eastus2.

.PARAMETER WhatIf
    Print every planned assignment without making any changes.

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
    [string] $Location            = 'eastus2'
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok]   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

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
#  Allowed resource types -- all L1-L4 lab resources                            #
# ---------------------------------------------------------------------------- #
$AllowedResourceTypes = @(
    # Networking -- L1 (hub/spoke, Bastion, peering)
    'Microsoft.Network/virtualNetworks'
    'Microsoft.Network/virtualNetworks/subnets'
    'Microsoft.Network/virtualNetworkPeerings'
    'Microsoft.Network/networkInterfaces'
    'Microsoft.Network/networkSecurityGroups'
    'Microsoft.Network/publicIPAddresses'
    'Microsoft.Network/bastionHosts'

    # Networking -- L2 (Firewall, route tables, LB)
    'Microsoft.Network/azureFirewalls'
    'Microsoft.Network/firewallPolicies'
    'Microsoft.Network/firewallPolicies/ruleCollectionGroups'
    'Microsoft.Network/routeTables'
    'Microsoft.Network/loadBalancers'

    # Networking -- L3 (private endpoints, DNS)
    'Microsoft.Network/privateDnsZones'
    'Microsoft.Network/privateDnsZones/virtualNetworkLinks'
    'Microsoft.Network/privateEndpoints'

    # Networking -- L4 (Front Door -- both classic and Standard/Premium)
    'Microsoft.Network/frontdoors'
    'Microsoft.Cdn/profiles'
    'Microsoft.Cdn/profiles/afdEndpoints'
    'Microsoft.Cdn/profiles/originGroups'
    'Microsoft.Cdn/profiles/originGroups/origins'
    'Microsoft.Cdn/profiles/routes'

    # Compute -- L1 / L2 VMs
    'Microsoft.Compute/virtualMachines'
    'Microsoft.Compute/disks'
    'Microsoft.Compute/virtualMachineExtensions'

    # Containers -- L3
    'Microsoft.App/managedEnvironments'
    'Microsoft.App/containerApps'

    # Data -- L3/L4
    'Microsoft.Sql/servers'
    'Microsoft.Sql/servers/databases'
    'Microsoft.Sql/servers/failoverGroups'
    'Microsoft.Sql/servers/firewallRules'
    'Microsoft.KeyVault/vaults'

    # Identity
    'Microsoft.ManagedIdentity/userAssignedIdentities'

    # Monitoring -- L3
    'Microsoft.OperationalInsights/workspaces'
    'Microsoft.Insights/components'
    'Microsoft.Insights/metricAlerts'
    'Microsoft.Insights/actionGroups'

    # ARM / RBAC plumbing
    'Microsoft.Authorization/roleAssignments'
    'Microsoft.Resources/deployments'
)

# ---------------------------------------------------------------------------- #
#  Built-in policy definition IDs                                               #
# ---------------------------------------------------------------------------- #
$PolicyAllowedLocations    = 'e56962a6-4747-49cd-b67b-bf8b01975c4f'  # Allowed locations
$PolicyAllowedResourceTypes = 'a08ec900-254a-4555-9bf5-e42af04b5c5c' # Allowed resource types
$PolicyInheritTag           = 'ea3f2387-9b95-492a-a190-fcdc54f7b070' # Inherit a tag from RG

# ---------------------------------------------------------------------------- #
#  Prerequisites                                                                #
# ---------------------------------------------------------------------------- #
Write-Step 'Checking prerequisites'

# Verify both required Az modules (Az.Accounts for context, Az.Resources for policy)
foreach ($ModuleName in 'Az.Accounts', 'Az.Resources') {
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Fail "Required module '$ModuleName' not found.`n  Run: Install-Module Az -Scope CurrentUser -Force"
    }
}

# Check Azure sign-in and subscription context -- guard against null context
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
        Fail "Cannot switch to subscription '$SubscriptionId'. Verify the ID in the CSV.`n  $($_.Exception.Message)"
    }
}
Write-Ok "Subscription: $SubscriptionId"

# Resolve built-in policy definitions once
Write-Step 'Resolving built-in policy definitions'

$DefAllowedLocations     = Get-AzPolicyDefinition -Id "/providers/Microsoft.Authorization/policyDefinitions/$PolicyAllowedLocations"
$DefAllowedResourceTypes = Get-AzPolicyDefinition -Id "/providers/Microsoft.Authorization/policyDefinitions/$PolicyAllowedResourceTypes"
$DefInheritTag           = Get-AzPolicyDefinition -Id "/providers/Microsoft.Authorization/policyDefinitions/$PolicyInheritTag"

Write-Ok "Allowed locations:     $($DefAllowedLocations.Properties.DisplayName)"
Write-Ok "Allowed resource types: $($DefAllowedResourceTypes.Properties.DisplayName)"
Write-Ok "Inherit tag:           $($DefInheritTag.Properties.DisplayName)"

if ($WhatIfPreference) { Write-Host "`n  *** DRY RUN -- no changes will be made ***`n" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------- #
#  Helper: ensure one policy assignment on a given scope                       #
# ---------------------------------------------------------------------------- #
function Ensure-PolicyAssignment {
    param(
        [string] $AssignmentName,
        [string] $DisplayName,
        [object] $PolicyDefinition,
        [string] $Scope,
        [hashtable] $Parameters
    )

    $Existing = Get-AzPolicyAssignment -Name $AssignmentName -Scope $Scope -ErrorAction SilentlyContinue

    if ($Existing) {
        Write-Skip "Policy '$DisplayName' already assigned on $Scope"
        return
    }

    if ($PSCmdlet.ShouldProcess($Scope, "Assign policy: $DisplayName")) {
        $NewAssignArgs = @{
            Name                 = $AssignmentName
            DisplayName          = $DisplayName
            Scope                = $Scope
            PolicyDefinition     = $PolicyDefinition
            PolicyParameterObject = $Parameters
        }
        New-AzPolicyAssignment @NewAssignArgs | Out-Null
        Write-Ok "Assigned: $DisplayName  ->  $Scope"
    } else {
        Write-Skip "Would assign: $DisplayName  ->  $Scope"
    }
}

# ---------------------------------------------------------------------------- #
#  Main loop -- one set of assignments per matching resource group               #
# ---------------------------------------------------------------------------- #
Write-Step "Finding resource groups matching prefix '$ResourceGroupPrefix'"

$TargetRGs = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "$ResourceGroupPrefix*" }

if (-not $TargetRGs) {
    Write-Warn "No resource groups found matching '$ResourceGroupPrefix'. Run New-LabEnvironment.ps1 first."
    exit 0
}

Write-Ok "Found $($TargetRGs.Count) matching resource groups"

$AssignedCount = 0

foreach ($RG in $TargetRGs) {
    $RgName = $RG.ResourceGroupName
    $RgScope = "/subscriptions/$SubscriptionId/resourceGroups/$RgName"

    Write-Step "Applying policies to $RgName"

    # 1. Allowed locations
    Ensure-PolicyAssignment `
        -AssignmentName "lab-loc-$RgName" `
        -DisplayName    "Lab: Allowed locations ($RgName)" `
        -PolicyDefinition $DefAllowedLocations `
        -Scope          $RgScope `
        -Parameters     @{ listOfAllowedLocations = @{ value = @($Location) } }

    # 2. Allowed resource types
    Ensure-PolicyAssignment `
        -AssignmentName "lab-rtype-$RgName" `
        -DisplayName    "Lab: Allowed resource types ($RgName)" `
        -PolicyDefinition $DefAllowedResourceTypes `
        -Scope          $RgScope `
        -Parameters     @{ listOfAllowedResourceTypes = @{ value = $AllowedResourceTypes } }

    # 3-6. Tag inheritance (one assignment per tag)
    foreach ($TagName in 'Owner', 'Event', 'Date', 'Instructor') {
        # Shorten assignment name -- Azure limit is 64 chars
        $ShortRg = $RgName -replace '^rg-techdemo-', ''
        Ensure-PolicyAssignment `
            -AssignmentName "lab-tag-$TagName-$ShortRg" `
            -DisplayName    "Lab: Inherit $TagName tag ($RgName)" `
            -PolicyDefinition $DefInheritTag `
            -Scope          $RgScope `
            -Parameters     @{ tagName = @{ value = $TagName } }
    }

    $AssignedCount++
}

# ---------------------------------------------------------------------------- #
#  Summary                                                                      #
# ---------------------------------------------------------------------------- #
Write-Host "`n$('=' * 72)" -ForegroundColor Green
Write-Host " POLICY ASSIGNMENTS COMPLETE" -ForegroundColor Green
Write-Host "$('=' * 72)" -ForegroundColor Green
Write-Host "  Resource groups processed : $AssignedCount"
Write-Host "  Assignments per group     : 6  (location + resource types + 4 tags)"
Write-Host "  Allowed location          : $Location"
Write-Host "  Resource type whitelist   : $($AllowedResourceTypes.Count) types"
if ($WhatIfPreference) {
    Write-Host "`n  *** DRY RUN -- no changes were made ***" -ForegroundColor Yellow
}
Write-Host ''
