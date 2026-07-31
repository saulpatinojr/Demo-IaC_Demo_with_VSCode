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
            (use -ResourceGroup).
      5. Pushes the required IDs as GitHub Actions secrets, sets AZURE_PREFIX
         and AZURE_LOCATION as repo variables, and generates strong throwaway
         VM/SQL passwords as secrets.

    You normally run this with -ResourceGroup set to the resource group your
    instructor assigned. Everything else is derived from the tools you are
    already signed in to. It is safe to re-run - each step checks for existing
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
    labs where you have been assigned a single resource group. This parameter
    is required for real runs because deploy workflows expect AZURE_RESOURCE_GROUP.

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
$createdApp = $false
$createdSp = $false
$createdRoleAssignment = $false
$createdFederatedCredentialNames = @()
$scope = ''

# Derive a unique app name from the prefix so each participant gets their own
# Entra app registration and avoid collisions in a shared tenant.
if (-not $AppName) { $AppName = "iac-demo-$Prefix" }

function Write-Banner($text) {
    $line = '=' * ($text.Length + 8)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host "  === $text ===" -ForegroundColor Yellow
    Write-Host "  $line" -ForegroundColor Yellow
    Write-Host ""
}
function Write-Step($msg)  { Write-Host ""; Write-Host "  > $msg" -ForegroundColor White }
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg)  { Write-Host "    [SKIP] $msg" -ForegroundColor DarkGray }
function Write-Warn($msg)  { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "    [FAIL] $msg" -ForegroundColor Red }
function Fail($msg)        { throw $msg }
$TopLevelCmdlet = $PSCmdlet

try {
    Write-Banner 'GitHub <-> Azure OIDC Setup'

    # --- 0. Tooling / auth checks --------------------------------------------
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
    if (-not $ResourceGroup -and -not $WhatIfPreference) {
        Fail 'ResourceGroup is required for this repo because deploy workflows require AZURE_RESOURCE_GROUP.'
    }
    Write-Ok 'az and gh are installed and signed in'

    # --- 1. Resolve GitHub repo ----------------------------------------------
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

    # Verify repo permissions up-front to avoid late partial Azure changes.
    gh secret list --repo $GitHubRepo --json name --jq '.[].name' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "Cannot list secrets for $GitHubRepo. Ensure gh has repo admin/write access."
    }
    gh variable list --repo $GitHubRepo --json name --jq '.[].name' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "Cannot list variables for $GitHubRepo. Ensure gh has repo admin/write access."
    }
    Write-Ok 'GitHub repo secrets/variables are accessible'

    # --- 2. Resolve subscription/tenant -------------------------------------
    Write-Step 'Resolving Azure subscription'
    if (-not $SubscriptionId) { $SubscriptionId = az account show --query id -o tsv }
    $TenantId = az account show --query tenantId -o tsv
    az account set --subscription $SubscriptionId
    Write-Ok "Subscription: $SubscriptionId"
    Write-Ok "Tenant:       $TenantId"

    # --- 2b. Validate classroom resource group scope -------------------------
    if ($ResourceGroup) {
        Write-Step 'Validating target resource group access'
        $rgExists = az group exists --name $ResourceGroup --subscription $SubscriptionId
        if ($rgExists -ne 'true') {
            Fail "Resource group '$ResourceGroup' does not exist in subscription '$SubscriptionId'."
        }

        az group show --name $ResourceGroup --subscription $SubscriptionId --query name -o tsv 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail "Resource group '$ResourceGroup' exists but is not accessible with the current account."
        }
        Write-Ok "resource group '$ResourceGroup' exists and is accessible"
    }

    # --- 3. App registration + service principal -----------------------------
    Write-Step "Ensuring Entra app registration '$AppName'"
    $appId = az ad app list --display-name $AppName --query '[0].appId' -o tsv
    if (-not $appId) {
        if ($TopLevelCmdlet.ShouldProcess($AppName, 'Create app registration')) {
            $appId = az ad app create --display-name $AppName --query appId -o tsv
            $createdApp = $true
            Write-Ok "Created app. appId=$appId"
        } else { Write-Skip 'would create app registration'; $appId = '<app-id>' }
    } else {
        Write-Skip "app already exists. appId=$appId"
    }

    $spId = az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv 2>$null
    if (-not $spId) {
        if ($TopLevelCmdlet.ShouldProcess($appId, 'Create service principal')) {
            az ad sp create --id $appId | Out-Null
            $createdSp = $true
            Write-Ok 'Created service principal'
        } else { Write-Skip 'would create service principal' }
    } else {
        Write-Skip 'service principal already exists'
    }

    # --- 4. Federated credentials (branch + pull_request) -------------------
    Write-Step 'Ensuring federated credentials (passwordless login)'
    function Set-FederatedCredentialIfMissing {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [string] $name,
            [string] $subject
        )
        $existing = az ad app federated-credential list --id $appId --query "[?subject=='$subject'] | [0].name" -o tsv 2>$null
        if ($existing) { Write-Skip "credential for '$subject' already exists"; return }
        if (-not $TopLevelCmdlet.ShouldProcess($subject, "Create federated credential '$name'")) {
            Write-Skip "would create credential '$name' for '$subject'"; return
        }
        $params = @{ name = $name; issuer = $issuer; subject = $subject; audiences = @($audience) } | ConvertTo-Json -Compress
        $created = $false
        for ($i = 1; $i -le 5; $i++) {
            $tmp = New-TemporaryFile
            try {
                Set-Content -Path $tmp -Value $params -Encoding utf8
                az ad app federated-credential create --id $appId --parameters "@$tmp" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $created = $true
                    break
                }
            } finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 3
        }

        if (-not $created) {
            Fail "Failed to create federated credential '$name' after retries. Re-run in ~30s."
        }
        $script:createdFederatedCredentialNames += $name
        Write-Ok "created credential '$name'"
    }
    Set-FederatedCredentialIfMissing "gh-$Branch" $subjectMain
    Set-FederatedCredentialIfMissing 'gh-pull-request' $subjectPR   # lets PR validation runs authenticate too

    # --- 5. Role assignment: Contributor at resource group scope ------------
    Write-Step 'Ensuring Contributor role assignment'
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
    Write-Ok "Scoping to resource group: $ResourceGroup"
    $hasRole = az role assignment list --assignee $appId --scope $scope --role Contributor --query '[0].id' -o tsv 2>$null
    if ($hasRole) {
        Write-Skip 'Contributor already assigned'
    } elseif ($TopLevelCmdlet.ShouldProcess($scope, 'Assign Contributor')) {
        # SP propagation can lag app creation by a few seconds; retry briefly.
        for ($i = 1; $i -le 5; $i++) {
            az role assignment create --assignee $appId --role Contributor --scope $scope 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Seconds 5
        }
        if ($LASTEXITCODE -ne 0) { Fail 'Role assignment failed (identity may still be propagating). Re-run in ~30s.' }
        $createdRoleAssignment = $true
        Write-Ok 'assigned Contributor'
    } else {
        Write-Skip 'would assign Contributor'
    }

    # --- 6. GitHub secrets & variables --------------------------------------
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
    function Set-RepoSecret {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [string] $name,
            [string] $value
        )
        $existingSecrets = @(gh secret list --repo $GitHubRepo --json name --jq '.[].name' 2>$null)
        if ($existingSecrets -contains $name) {
            Write-Skip "secret '$name' already exists"
            return
        }
        if ($TopLevelCmdlet.ShouldProcess("$GitHubRepo secret $name", 'Set')) {
            $value | gh secret set $name --repo $GitHubRepo --body - 2>$null
            if ($LASTEXITCODE -ne 0) {
                Fail "Failed to set secret $name"
            }
            Write-Ok "secret $name set"
        } else { Write-Skip "would set secret $name" }
    }
    function Set-RepoVariable {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [string] $name,
            [string] $value
        )
        $existingVars = @(gh variable list --repo $GitHubRepo --json name --jq '.[].name' 2>$null)
        if ($existingVars -contains $name) {
            Write-Skip "variable '$name' already exists"
            return
        }
        if ($TopLevelCmdlet.ShouldProcess("$GitHubRepo variable $name", 'Set')) {
            gh variable set $name --repo $GitHubRepo --body $value 2>$null
            if ($LASTEXITCODE -ne 0) {
                Fail "Failed to set variable $name"
            }
            Write-Ok "variable $name = $value"
        } else { Write-Skip "would set variable $name = $value" }
    }
    Set-RepoSecret 'AZURE_CLIENT_ID'       $appId
    Set-RepoSecret 'AZURE_TENANT_ID'       $TenantId
    Set-RepoSecret 'AZURE_SUBSCRIPTION_ID' $SubscriptionId
    Set-RepoSecret 'VM_ADMIN_PASSWORD'  (New-ThrowawayPassword)
    Set-RepoSecret 'SQL_ADMIN_PASSWORD' (New-ThrowawayPassword)
    Set-RepoSecret 'AZURE_RESOURCE_GROUP' $ResourceGroup

    # Prefix and location are non-secret variables (they appear in resource names/logs).
    Set-RepoVariable 'AZURE_PREFIX'   $Prefix
    Set-RepoVariable 'AZURE_LOCATION' $Location

    if ($AlertEmail) {
        Write-Step 'Setting ALERT_EMAIL variable (L3)'
        Set-RepoVariable 'ALERT_EMAIL' $AlertEmail
    }

    # --- 7. Validate secret/variable presence -------------------------------
    if (-not $WhatIfPreference) {
        Write-Step 'Validating GitHub secrets and variables'

        $secretNames = @(
            'AZURE_CLIENT_ID',
            'AZURE_TENANT_ID',
            'AZURE_SUBSCRIPTION_ID',
            'VM_ADMIN_PASSWORD',
            'SQL_ADMIN_PASSWORD',
            'AZURE_RESOURCE_GROUP'
        )

        $variableNames = @('AZURE_PREFIX', 'AZURE_LOCATION')
        if ($AlertEmail) {
            $variableNames += 'ALERT_EMAIL'
        }

        $repoSecrets = gh secret list --repo $GitHubRepo --json name --jq '.[].name' 2>$null
        $repoVars    = gh variable list --repo $GitHubRepo --json name --jq '.[].name' 2>$null

        $missingSecret = @($secretNames | Where-Object { $repoSecrets -notcontains $_ })
        $missingVar    = @($variableNames | Where-Object { $repoVars -notcontains $_ })

        if ($missingSecret.Count -gt 0) {
            foreach ($s in $missingSecret) {
                Write-Warn "Missing secret: $s"
            }
            Fail 'One or more required GitHub secrets are missing after setup. Re-run this script.'
        }

        if ($missingVar.Count -gt 0) {
            foreach ($v in $missingVar) {
                Write-Warn "Missing variable: $v"
            }
            Fail 'One or more required GitHub variables are missing after setup. Re-run this script.'
        }

        Write-Ok 'required secrets and variables are present'
    }

    # --- Done ----------------------------------------------------------------
    Write-Banner 'OIDC Setup Complete'
    if ($WhatIfPreference) {
        Write-Warn 'DRY RUN complete - nothing was changed. Re-run without -WhatIf.'
    } else {
        Write-Ok 'OIDC handshake complete. GitHub can now deploy to Azure with no stored cloud credentials.'
        Write-Ok "Next: GitHub -> Actions -> 'Deploy L1 - Hub & Spoke' -> Run workflow."
        Write-Host "    (Throwaway VM/SQL passwords were generated and stored as secrets;" -ForegroundColor DarkGray
        Write-Host "     you never need to see them. Re-run this script to rotate.)" -ForegroundColor DarkGray
        if ($ResourceGroup) {
            Write-Ok "Resource group: $ResourceGroup  |  Prefix: $Prefix  |  Location: $Location"
        }
    }
}
catch {
    $errText = $_.Exception.Message
    Write-Fail "ERROR: $errText"

    if (-not $WhatIfPreference -and $createdRoleAssignment -and $appId -and $scope) {
        Write-Step 'Rollback: removing Contributor role assignment created by this run'
        az role assignment delete --assignee $appId --role Contributor --scope $scope 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'removed Contributor role assignment' }
        else { Write-Warn 'unable to remove role assignment automatically' }
    }

    if (-not $WhatIfPreference -and $appId -and $createdFederatedCredentialNames.Count -gt 0) {
        Write-Step 'Rollback: removing federated credentials created by this run'
        foreach ($fcName in $createdFederatedCredentialNames) {
            az ad app federated-credential delete --id $appId --federated-credential-id $fcName 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Ok "removed federated credential '$fcName'" }
            else { Write-Warn "unable to remove federated credential '$fcName' automatically" }
        }
    }

    if (-not $WhatIfPreference -and $createdSp -and $appId) {
        Write-Step 'Rollback: removing service principal created by this run'
        az ad sp delete --id $appId 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'removed service principal' }
        else { Write-Warn 'unable to remove service principal automatically' }
    }

    if (-not $WhatIfPreference -and $createdApp -and $appId) {
        Write-Step 'Rollback: removing app registration created by this run'
        az ad app delete --id $appId 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'removed app registration' }
        else { Write-Warn 'unable to remove app registration automatically' }
    }

    exit 1
}
