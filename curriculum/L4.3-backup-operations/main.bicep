// ============================================================================
// L4.3 — Operational Backup Management (builds on L4.1 and L4.2)
// Backup stops being a configuration and becomes a service: the vault reports
// into the Level 2 workspace, failed and missed jobs page the Level 2 action
// group, and the multi-user authorization design is deployed far enough to be
// understood without pretending it is complete.
//
// The alert here is the point of the chapter. A backup system that fails
// silently is worse than none, because it produces confidence without
// producing recovery points -- and "no news" is exactly what a broken backup
// job looks like from the outside.
//
// Cost: Backup center, reports and Resource Guard are free. You pay for the
// ~0.05 GB/day of job telemetry (~$0.14/day) and for whatever a restore drill
// temporarily creates.
//
// Prerequisite: L4.1 (the vault), L2.1 (the workspace), L2.3 (the action group).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace the vault reports into. Defaults to the one L2.1 filled.')
param workspaceName string = 'log-${prefix}-l3'

@description('Action group backup failures notify. Defaults to the one L2.3 created.')
param actionGroupName string = 'ag-${prefix}-oncall'

@description('Create a Resource Guard for multi-user authorization. OFF by default, and read the wiki page before turning it on: a Resource Guard in the SAME subscription with the SAME administrators protects against accident but not against a compromised admin, which is what MUA exists for. Associating it with the vault also needs a role assignment, which plain Contributor cannot create.')
param deployResourceGuard bool = false

var vaultName = 'rsv-${prefix}-backup'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' existing = {
  name: actionGroupName
}

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
}

// ---------------------------------------------------------------------------
// The vault's own telemetry. Named categories again, not allLogs: these five
// are what Backup reports and the alert below are built on, and the rest is
// volume without a reader.
// ---------------------------------------------------------------------------
resource vaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-workspace'
  scope: vault
  properties: {
    workspaceId: workspace.id
    // Resource-specific tables (AddonAzureBackupJobs and friends) rather than
    // the legacy AzureDiagnostics blob. Queries stay readable and the columns
    // are typed.
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'CoreAzureBackup', enabled: true }
      { category: 'AddonAzureBackupJobs', enabled: true }
      { category: 'AddonAzureBackupAlerts', enabled: true }
      { category: 'AddonAzureBackupPolicy', enabled: true }
      { category: 'AddonAzureBackupProtectedInstance', enabled: true }
    ]
  }
}

// ---------------------------------------------------------------------------
// The alert that makes backup an operational service. Note what it watches:
// FAILED jobs, and separately the ABSENCE of successful ones. Only the second
// catches a job that stopped being scheduled at all.
// ---------------------------------------------------------------------------
resource failedJobAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${prefix}-backup-failed'
  location: location
  properties: {
    displayName: 'A backup job failed'
    description: 'Any Azure Backup job in a Failed state in the last 12 hours.'
    severity: 1
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT12H'
    criteria: {
      allOf: [
        {
          query: 'AddonAzureBackupJobs\n| where JobStatus == "Failed"\n| summarize Failures = count() by BackupItemUniqueId, JobOperation'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// The dangerous one. A job that fails raises an alert; a job that was never
// scheduled raises nothing at all, and that is the failure mode that costs
// people their data. This rule fires on silence.
resource noSuccessAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${prefix}-backup-silent'
  location: location
  properties: {
    displayName: 'No successful backup in 36 hours'
    description: 'Fires when nothing has completed successfully in 36 hours — the daily schedule has had at least one chance and missed it. "No news" is what a broken backup system looks like.'
    severity: 1
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT36H'
    criteria: {
      allOf: [
        {
          query: 'AddonAzureBackupJobs\n| where JobOperation == "Backup" and JobStatus == "Completed"\n| summarize Successes = count()\n| where Successes == 0'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// ---------------------------------------------------------------------------
// Multi-user authorization, as far as a Contributor can honestly take it.
// The guard deploys; associating it with the vault does not, because that
// needs a role assignment on the guard for the vault's operators.
// ---------------------------------------------------------------------------
resource resourceGuard 'Microsoft.DataProtection/resourceGuards@2024-04-01' = if (deployResourceGuard) {
  name: 'rg-${prefix}-backup-guard'
  location: location
  properties: {}
}

output vaultDiagnosticsCategories int = 5
output alertRules array = ['alert-${prefix}-backup-failed', 'alert-${prefix}-backup-silent']
output whyTwoAlerts string = 'A failed job raises an alert. A job that was never scheduled raises nothing — only the silence rule catches that, and it is the failure mode that actually loses data.'
output resourceGuardDeployed bool = deployResourceGuard
output muaIsIncomplete string = deployResourceGuard
  ? 'Resource Guard created. It is NOT associated with the vault: that needs a role assignment on the guard, which plain Contributor cannot create. And a guard in the same subscription with the same admins stops accidents, not attackers.'
  : 'No Resource Guard. Real MUA puts the guard in a different subscription under different administrators — otherwise the person who can delete the backups can also disable the thing stopping them.'
output monthlyCost string = 'Backup center, reports, alerts on existing data and Resource Guard are free. The cost is ~0.05 GB/day of job telemetry (~$4/month) plus $1-2 per restore drill.'
