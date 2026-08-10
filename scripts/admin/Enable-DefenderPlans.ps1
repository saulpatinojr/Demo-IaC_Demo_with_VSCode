<#
.SYNOPSIS
    Enables the Microsoft Defender for Cloud plans the curriculum's Level 3
    needs, at subscription scope, by deploying defender-plans.bicep.

.DESCRIPTION
    Defender plans are a SUBSCRIPTION-scoped resource
    (Microsoft.Security/pricings). Lab participants hold Contributor on a
    single resource group, which cannot enable them at any price -- so this is
    an instructor job, run once per lab subscription, exactly like
    Set-LabPolicy.ps1.

    The plans themselves are declared in defender-plans.bicep, next to this
    script -- the same tool the students use, reviewable in the same pull
    requests. This wrapper adds the one thing a template cannot do: per-node
    pricing bills whatever already lives in the subscription, and only a
    reader can count that. The script counts, prints what each plan will cost
    against the resources it can see, and only then deploys. -WhatIf runs the
    deployment's own what-if and changes nothing.

    Rates (East US 2, US retail list, verified 2026-08-08):

        Defender CSPM (paid)            $0.007  /resource/hr   (~$5.11/mo)
        Defender for Servers Plan 1     $0.00672/node/hr       (~$4.91/mo)
        Defender for Servers Plan 2     $0.02   /node/hr       (~$14.60/mo)
        Defender for SQL                $0.0202 /instance/hr   (~$14.72/mo)
        Defender for Key Vault          $0.00034/node/hr       (~$0.25/mo)
        Defender for Resource Manager   $0.0069 /node/hr       (~$5.04/mo)
        Defender for Storage            $0.0134 /account/hr    (~$9.78/mo)

    Foundational CSPM -- secure score, recommendations, the Microsoft Cloud
    Security Benchmark -- is free and always on. L3.1 runs entirely on it, and
    nothing here is needed until L3.2.

    Every plan carries a 30-day free trial per subscription. Scheduling Level 3
    inside that window makes this script free once.

.PREREQUISITES
    PowerShell 7 and Azure CLI, signed in with an account holding
    Security Admin or Owner on the target subscription. Contributor is not
    enough: Microsoft.Security/pricings/write is not in its actions.

.PARAMETER SubscriptionId
    Subscription to enable plans on. Defaults to the current az CLI context.

.PARAMETER ServersPlan
    'P1' (default) or 'P2'. P2 adds vulnerability assessment, file integrity
    monitoring and just-in-time VM access -- L3.2's JIT exercise needs it --
    at three times the price. 'None' skips Defender for Servers entirely.

.PARAMETER IncludeStorage
    Also enable Defender for Storage. Off by default: the lab deploys no
    storage account of its own, so this only bills for whatever else lives in
    the subscription.

.EXAMPLE
    # Preview -- changes nothing
    ./scripts/admin/Enable-DefenderPlans.ps1 -WhatIf

.EXAMPLE
    # The set L3.2 assumes
    ./scripts/admin/Enable-DefenderPlans.ps1 -ServersPlan P1

.EXAMPLE
    # Turn everything back off when the class is over
    ./scripts/admin/Enable-DefenderPlans.ps1 -Disable
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $SubscriptionId,
    [ValidateSet('None', 'P1', 'P2')]
    [string] $ServersPlan = 'P1',
    [switch] $IncludeStorage,
    [switch] $Disable
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Write-Cost($msg) { Write-Host "    [cost] $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

$TemplateFile = Join-Path $PSScriptRoot 'defender-plans.bicep'
if (-not (Test-Path $TemplateFile)) { Fail "Template not found: $TemplateFile" }

# ---------------------------------------------------------------------------- #
#  Context                                                                      #
# ---------------------------------------------------------------------------- #
Write-Step 'Checking Azure CLI context'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Fail 'Azure CLI not found. Install it, then run az login.'
}

if (-not $SubscriptionId) {
    $SubscriptionId = az account show --query id -o tsv 2>$null
    if (-not $SubscriptionId) { Fail 'Not signed in. Run az login first.' }
    Write-Ok "using the current context: $SubscriptionId"
} else {
    az account set --subscription $SubscriptionId 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "Cannot select subscription $SubscriptionId." }
    Write-Ok "subscription set: $SubscriptionId"
}

$subName = az account show --query name -o tsv
Write-Ok "name: $subName"

# ---------------------------------------------------------------------------- #
#  Count what the plans will bill for BEFORE enabling anything                   #
# ---------------------------------------------------------------------------- #
# Per-node pricing means the bill is a function of what is already in the
# subscription, not of what the lab deployed. An instructor running this
# against a shared subscription should see that number first. This is the
# part that stays PowerShell: a template declares desired state, it cannot
# count what already exists.
Write-Step 'Counting billable resources across the whole subscription'

$vmCount  = [int](az vm list --query 'length(@)' -o tsv 2>$null)
$sqlCount = [int](az sql server list --query 'length(@)' -o tsv 2>$null)
$kvCount  = [int](az keyvault list --query 'length(@)' -o tsv 2>$null)
$stCount  = [int](az storage account list --query 'length(@)' -o tsv 2>$null)

Write-Ok "virtual machines: $vmCount"
Write-Ok "SQL servers: $sqlCount"
Write-Ok "key vaults: $kvCount"
Write-Ok "storage accounts: $stCount"

$serverRate = switch ($ServersPlan) { 'P2' { 0.02 } 'P1' { 0.00672 } default { 0 } }
$hourly  = ($vmCount * $serverRate) + ($sqlCount * 0.0202) + ($kvCount * 0.00034) + 0.0069
if ($IncludeStorage) { $hourly += $stCount * 0.0134 }
$monthly = $hourly * 730

Write-Cost ('estimated {0:N4}/hr, about {1:N2}/month, for the ENTIRE subscription' -f $hourly, $monthly)
if ($vmCount -gt 10) {
    Write-Warn "This subscription has $vmCount VMs. Per-node plans bill for all of them, not just the lab's."
}

# ---------------------------------------------------------------------------- #
#  Deploy the template                                                          #
# ---------------------------------------------------------------------------- #
$enabled = (-not $Disable).ToString().ToLower()
$includeStorageValue = $IncludeStorage.IsPresent.ToString().ToLower()
$commonArgs = @(
    '--location', 'eastus2'
    '--name', 'lab-defender-plans'
    '--template-file', $TemplateFile
    '--parameters', "serversPlan=$ServersPlan", "includeStorage=$includeStorageValue", "enabled=$enabled"
)

$action = if ($Disable) { 'Disable Defender plans (tier -> Free)' } else { "Enable Defender plans (Servers $ServersPlan)" }

if ($WhatIfPreference) {
    Write-Step 'What-if -- no changes will be made'
    az deployment sub what-if @commonArgs
    if ($LASTEXITCODE -ne 0) { Fail 'what-if failed.' }
    exit 0
}

if (-not $PSCmdlet.ShouldProcess($subName, $action)) { exit 0 }

Write-Step $action
az deployment sub create @commonArgs --query 'properties.outputs' -o jsonc
if ($LASTEXITCODE -ne 0) {
    Fail 'Deployment failed. Do you hold Security Admin or Owner on this subscription?'
}

# ---------------------------------------------------------------------------- #
#  Report                                                                       #
# ---------------------------------------------------------------------------- #
Write-Step 'Current plan state'
az security pricing list --query "value[?pricingTier=='Standard'].{Plan:name, Tier:pricingTier, SubPlan:subPlan}" -o table 2>$null

if ($Disable) {
    Write-Host ''
    Write-Ok 'Plans set back to Free. Per-node charges stop; findings already raised remain visible.'
} else {
    Write-Host ''
    Write-Warn 'These plans bill per node across the whole subscription, every hour, until disabled.'
    Write-Host '    Turn them off when the class ends:' -ForegroundColor Yellow
    Write-Host '        ./scripts/admin/Enable-DefenderPlans.ps1 -Disable' -ForegroundColor Yellow
}
Write-Host ''
