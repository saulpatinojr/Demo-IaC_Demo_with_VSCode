<#
.SYNOPSIS
    One-command GitHub <-> Azure OIDC "handshake" for this workshop.

.DESCRIPTION
    Wires up passwordless deployment from GitHub Actions to Azure. It:
      1. Detects your GitHub owner/repo automatically (from the gh CLI).
      2. Creates (or reuses) an Entra ID app registration + service principal.
      3. Adds a federated credential so Actions on your branch can log in with
         NO stored client secret.
      4. Grants that identity Contributor on your assigned resource group
         (use -ResourceGroup) or on the full subscription (default, requires
         subscription-level permissions).
      5. Pushes the required IDs as GitHub Actions secrets, sets AZURE_PREFIX
         and AZURE_LOCATION as repo variables, and generates strong throwaway
         VM/SQL passwords as secrets.

    You normally run this with -ResourceGroup set to the resource group your
    instructor assigned. Everything else is derived from the tools you are
    already signed in to. It is safe to re-run — each step checks for existing
    objects first (idempotent).

.PREREQUISITES
    - Azure CLI  (az)  -> signed in:  az login
    - GitHub CLI (gh)  -> signed in:  gh auth login
    - You are running this from inside a clone of YOUR fork of the repo.

.PARAMETER GitHubRepo
    Override auto-detection. Format: "owner/repo". Default: detected via gh.

.PARAMETER Branch
    Branch the workflows run from. Default: main. A federated credential is
    created for this exact branch (that is the identity GitHub presents).

.PARAMETER AppName
    Display name of the Entra app registration. Defaults to "iac-demo-<Prefix>"
    so each participant automatically gets a uniquely named app. Override only
    if you need a specific name.

.PARAMETER SubscriptionId
    Target subscription. Default: your current az default subscription.

.PARAMETER ResourceGroup
    Resource group name to scope Contributor to. Recommended for classroom
    labs where you have been assigned a single resource group. If omitted,
    Contributor is granted at subscription scope (requires owner/admin perms).

.PARAMETER Prefix
    Unique prefix for resource names (e.g. your initials). Stored as the
    AZURE_PREFIX repo variable. Default: iacdemo. Use something unique to
    avoid naming conflicts with other lab participants.

.PARAMETER Location
    Azure region for all lab resources. Stored as the AZURE_LOCATION repo
    variable. Default: eastus2.

.PARAMETER AlertEmail
    If provided, also sets the ALERT_EMAIL repo *variable* used by L3.

.PARAMETER WhatIf
    Print every action without changing anything. Recommended first run.

.EXAMPLE
    ./scripts/Setup-Oidc.ps1 -WhatIf
    Preview exactly what would be created.

.EXAMPLE
    ./scripts/Setup-Oidc.ps1 -ResourceGroup "rg-lab-alice" -Prefix "alice"
    Typical classroom setup: scope to assigned RG with a unique prefix.

.EXAMPLE
    ./scripts/Setup-Oidc.ps1 -GitHubRepo "myorg/Demo-IaC_Demo_with_VSCode" -ResourceGroup "rg-lab-alice" -Prefix "alice" -AlertEmail "me@example.com"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $GitHubRepo,
    [string] $Branch = 'main',
    [string] $AppName = '',
    [string] $SubscriptionId,
    [string] $ResourceGroup,
    [string] $Prefix = 'iacdemo',
    [string] $Location = 'eastus2',
    [string] $AlertEmail
)

$ErrorActionPreference = 'Stop'
$issuer   = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'

# Derive a unique app name from the prefix so each participant gets their own
# Entra app registration and avoid collisions in a shared tenant.
if (-not $AppName) { $AppName = "iac-demo-$Prefix" }

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }
function Fail($msg)        { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

# --- 0. Tooling / auth checks ------------------------------------------------
Write-Step 'Checking prerequisites'
foreach ($t in 'az', 'gh') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Fail "$t is not installed or not on PATH. See the Wiki -> Start Here Checklist."
    }
}
try { az account show -o none 2>$null } catch { Fail 'Not signed in to Azure. Run:  az login' }
if ($LASTEXITCODE -ne 0) { Fail 'Not signed in to Azure. Run:  az login' }
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'Not signed in to GitHub. Run:  gh auth login' }
Write-Ok 'az and gh are installed and signed in'

# --- 1. Resolve GitHub repo --------------------------------------------------
Write-Step 'Resolving GitHub repository'
if (-not $GitHubRepo) {
    $GitHubRepo = (gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>$null)
    if (-not $GitHubRepo) {
        Fail 'Could not auto-detect the repo. Run this from inside your clone, or pass -GitHubRepo "owner/repo".'
    }
}
if ($GitHubRepo -notmatch '^[^/]+/[^/]+$') { Fail "GitHubRepo must be 'owner/repo'. Got: $GitHubRepo" }
$subjectMain = "repo:${GitHubRepo}:ref:refs/heads/$Branch"
$subjectPR   = "repo:${GitHubRepo}:pull_request"
Write-Ok "Repo:   $GitHubRepo"
Write-Ok "Branch: $Branch"
Write-Ok "OIDC subject: $subjectMain"

# --- 2. Resolve subscription/tenant -----------------------------------------
Write-Step 'Resolving Azure subscription'
if (-not $SubscriptionId) { $SubscriptionId = az account show --query id -o tsv }
$TenantId = az account show --query tenantId -o tsv
az account set --subscription $SubscriptionId
Write-Ok "Subscription: $SubscriptionId"
Write-Ok "Tenant:       $TenantId"

# --- 3. App registration + service principal --------------------------------
Write-Step "Ensuring Entra app registration '$AppName'"
$appId = az ad app list --display-name $AppName --query '[0].appId' -o tsv
if (-not $appId) {
    if ($PSCmdlet.ShouldProcess($AppName, 'Create app registration')) {
        $appId = az ad app create --display-name $AppName --query appId -o tsv
        Write-Ok "Created app. appId=$appId"
    } else { Write-Skip 'would create app registration'; $appId = '<app-id>' }
} else {
    Write-Skip "app already exists. appId=$appId"
}

$spId = az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv 2>$null
if (-not $spId) {
    if ($PSCmdlet.ShouldProcess($appId, 'Create service principal')) {
        az ad sp create --id $appId | Out-Null
        Write-Ok 'Created service principal'
    } else { Write-Skip 'would create service principal' }
} else {
    Write-Skip 'service principal already exists'
}

# --- 4. Federated credentials (branch + pull_request) -----------------------
Write-Step 'Ensuring federated credentials (passwordless login)'
function Ensure-FederatedCredential($name, $subject) {
    $existing = az ad app federated-credential list --id $appId --query "[?subject=='$subject'] | [0].name" -o tsv 2>$null
    if ($existing) { Write-Skip "credential for '$subject' already exists"; return }
    if (-not $PSCmdlet.ShouldProcess($subject, "Create federated credential '$name'")) {
        Write-Skip "would create credential '$name' for '$subject'"; return
    }
    $params = @{ name = $name; issuer = $issuer; subject = $subject; audiences = @($audience) } | ConvertTo-Json -Compress
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $params -Encoding utf8
    az ad app federated-credential create --id $appId --parameters "@$tmp" | Out-Null
    Remove-Item $tmp -Force
    Write-Ok "created credential '$name'"
}
Ensure-FederatedCredential "gh-$Branch" $subjectMain
Ensure-FederatedCredential 'gh-pull-request' $subjectPR   # lets PR validation runs authenticate too

# --- 5. Role assignment: Contributor at resource group or subscription scope --
Write-Step 'Ensuring Contributor role assignment'
if ($ResourceGroup) {
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    Write-Ok "Scoping to resource group: $ResourceGroup"
} else {
    $scope = "/subscriptions/$SubscriptionId"
    Write-Host '    [note] No -ResourceGroup specified — granting at subscription scope.' -ForegroundColor Yellow
    Write-Host '           This requires Owner or User Access Administrator on the subscription.' -ForegroundColor Yellow
}
$hasRole = az role assignment list --assignee $appId --scope $scope --role Contributor --query '[0].id' -o tsv 2>$null
if ($hasRole) {
    Write-Skip 'Contributor already assigned'
} elseif ($PSCmdlet.ShouldProcess($scope, 'Assign Contributor')) {
    # SP propagation can lag app creation by a few seconds; retry briefly.
    for ($i = 1; $i -le 5; $i++) {
        az role assignment create --assignee $appId --role Contributor --scope $scope 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 5
    }
    if ($LASTEXITCODE -ne 0) { Fail 'Role assignment failed (identity may still be propagating). Re-run in ~30s.' }
    Write-Ok 'assigned Contributor'
} else {
    Write-Skip 'would assign Contributor'
}

# --- 6. GitHub secrets & variables ------------------------------------------
Write-Step 'Setting GitHub Actions secrets and variables'
function New-ThrowawayPassword {
    # 20 chars, mixed classes; meets Azure VM + SQL complexity rules.
    $upper='ABCDEFGHJKLMNPQRSTUVWXYZ'; $lower='abcdefghijkmnpqrstuvwxyz'
    $num='23456789'; $sym='!@#$%^*-_'
    $all="$upper$lower$num$sym".ToCharArray()
    $pw  = ($upper[(Get-Random -Max $upper.Length)]) + ($lower[(Get-Random -Max $lower.Length)]) +
           ($num[(Get-Random -Max $num.Length)])     + ($sym[(Get-Random -Max $sym.Length)])
    1..16 | ForEach-Object { $pw += $all[(Get-Random -Max $all.Length)] }
    return $pw
}
function Set-RepoSecret($name, $value) {
    if ($PSCmdlet.ShouldProcess("$GitHubRepo secret $name", 'Set')) {
        $value | gh secret set $name --repo $GitHubRepo --body - 2>$null
        Write-Ok "secret $name set"
    } else { Write-Skip "would set secret $name" }
}
function Set-RepoVariable($name, $value) {
    if ($PSCmdlet.ShouldProcess("$GitHubRepo variable $name", 'Set')) {
        gh variable set $name --repo $GitHubRepo --body $value 2>$null
        Write-Ok "variable $name = $value"
    } else { Write-Skip "would set variable $name = $value" }
}
Set-RepoSecret 'AZURE_CLIENT_ID'       $appId
Set-RepoSecret 'AZURE_TENANT_ID'       $TenantId
Set-RepoSecret 'AZURE_SUBSCRIPTION_ID' $SubscriptionId
Set-RepoSecret 'VM_ADMIN_PASSWORD'  (New-ThrowawayPassword)
Set-RepoSecret 'SQL_ADMIN_PASSWORD' (New-ThrowawayPassword)
if ($ResourceGroup) {
    Set-RepoSecret 'AZURE_RESOURCE_GROUP' $ResourceGroup
}

# Prefix and location are non-secret variables (they appear in resource names/logs).
Set-RepoVariable 'AZURE_PREFIX'   $Prefix
Set-RepoVariable 'AZURE_LOCATION' $Location

if ($AlertEmail) {
    Write-Step 'Setting ALERT_EMAIL variable (L3)'
    Set-RepoVariable 'ALERT_EMAIL' $AlertEmail
}

# --- Done --------------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor Green
if ($WhatIfPreference) {
    Write-Host ' DRY RUN complete — nothing was changed. Re-run without -WhatIf.' -ForegroundColor Yellow
} else {
    Write-Host ' OIDC handshake complete. GitHub can now deploy to Azure' -ForegroundColor Green
    Write-Host ' with no stored cloud credentials.' -ForegroundColor Green
    Write-Host "`n Next: GitHub -> Actions -> 'Deploy L1 - Hub & Spoke' -> Run workflow." -ForegroundColor Green
    Write-Host " (Throwaway VM/SQL passwords were generated and stored as secrets;" -ForegroundColor DarkGray
    Write-Host "  you never need to see them. Re-run this script to rotate.)" -ForegroundColor DarkGray
    if ($ResourceGroup) {
        Write-Host "`n Resource group: $ResourceGroup  |  Prefix: $Prefix  |  Location: $Location" -ForegroundColor Green
    }
}
Write-Host '============================================================' -ForegroundColor Green
