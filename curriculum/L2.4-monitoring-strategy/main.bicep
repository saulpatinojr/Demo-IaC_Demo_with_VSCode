// ============================================================================
// L2.4 — Enterprise Monitoring Strategy (builds on L2.1–L2.3)
// The governing chapter, and the only one in the curriculum that should end
// with a SMALLER bill than it started: high-volume tables move to the Basic
// plan, long-tail retention moves to archive, a policy audits whether anyone
// forgot a diagnostic setting, and a budget puts a number on all of it.
//
// Two ownership boundaries are respected on purpose, and they are half the
// lesson:
//   * Workspace-level settings (retention, daily cap, SKU) belong to the
//     template that CREATES the workspace -- labs/L3-containers. This chapter
//     configures TABLES, which nothing else owns.
//   * The policy assignment is OFF by default and gated behind a parameter.
//     Contributor cannot create policy assignments at all -- the role's
//     notActions include Microsoft.Authorization/*/Write, which covers policy
//     assignments as well as role assignments. Classroom participants and the
//     OIDC identity both hold plain Contributor on one resource group, so
//     turning this on without Resource Policy Contributor fails the deploy.
//     Instructors have scripts/admin/Set-LabPolicy.ps1 for the same job.
//     It is AuditIfNotExists rather than DeployIfNotExists for a second
//     reason: DINE also needs a managed identity and a role assignment.
//
// Prerequisite: L2.1 (tables exist once data arrives), L2.3 (the action group
// the budget notifies).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Workspace whose tables are being re-planned. Defaults to the one L1.3 created.')
param workspaceName string = 'log-${prefix}-l3'

@description('Action group the budget alerts notify. Defaults to the one L2.3 created.')
param actionGroupName string = 'ag-${prefix}-oncall'

@description('Move the firewall application-rule table to the Basic plan. $0.50/GB instead of $2.76 — but Basic tables cannot be queried by alert rules, cannot be used in cross-resource joins, and get a fixed 30-day interactive retention. Nothing in L2.3 alerts on this table, which is exactly why it is the one being moved.')
param useBasicPlanForFirewallLogs bool = true

@description('Total retention for the security-relevant tables, in days. Anything beyond the included 31 days bills at $0.12/GB/month interactive, or $0.02/GB/month once it falls into the archive.')
@minValue(31)
@maxValue(730)
param totalRetentionDays int = 180

@description('Monthly budget for the resource group, in USD. The default is one month of the full L1–L2 stack at about $1.93/hr, rounded up.')
@minValue(10)
param monthlyBudgetUsd int = 1450

@description('First day of the month the budget starts. Defaults to the current month — budgets reject a start date that is not the first of a month.')
param budgetStartDate string = '${utcNow('yyyy-MM')}-01T00:00:00Z'

@description('Assign the diagnostic-settings audit policy. OFF by default because plain Contributor cannot create a policy assignment — the role excludes Microsoft.Authorization/*/Write. Turn it on only if you hold Resource Policy Contributor or Owner on the resource group; otherwise read the compliance view your instructor already assigned.')
param assignAuditPolicy bool = false

@description('Where budget alerts go directly. The budget API requires at least one contact email even when an action group is also attached, so this is not optional.')
param alertEmail string = 'you@example.com'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' existing = {
  name: actionGroupName
}

// ---------------------------------------------------------------------------
// Table plans. This is where the saving is.
//
// AZFWApplicationRule is the highest-volume table L2.1 turned on and nothing
// queries it interactively — it is evidence, not signal. On the Basic plan it
// costs $0.50/GB instead of $2.76, an 82% cut on that table.
//
// Basic tables take a FIXED 30-day interactive retention, so retentionInDays
// must not be set here; only total retention (the archive tail) is settable.
// ---------------------------------------------------------------------------
resource firewallAppRuleTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = if (useBasicPlanForFirewallLogs) {
  parent: workspace
  name: 'AZFWApplicationRule'
  properties: {
    plan: useBasicPlanForFirewallLogs ? 'Basic' : 'Analytics'
    totalRetentionInDays: totalRetentionDays
  }
}

// Syslog stays on Analytics. It has to: L2.3's "syslog errors spiking" rule
// queries it, and alert rules cannot read Basic tables. Moving this table to
// save $2.26/GB would silently break a rule somebody is relying on — which is
// the trap this chapter exists to teach.
resource syslogTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: workspace
  name: 'Syslog'
  properties: {
    plan: 'Analytics'
    retentionInDays: 31
    totalRetentionInDays: totalRetentionDays
  }
}

// Heartbeat is tiny and load-bearing — the "a VM stopped reporting" rule reads
// it. Interactive retention stays at the included 31 days; there is nothing to
// gain from archiving a table this small.
resource heartbeatTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: workspace
  name: 'Heartbeat'
  properties: {
    plan: 'Analytics'
    retentionInDays: 31
    totalRetentionInDays: 31
  }
}

// ---------------------------------------------------------------------------
// Governance. Off unless you have the rights for it: creating a policy
// assignment needs Resource Policy Contributor or Owner, and this lab hands
// out Contributor. When it is on, the compliance view answers "did anyone add
// a resource and forget to wire it up", which is the question that actually
// matters at a hundred environments.
// ---------------------------------------------------------------------------
resource diagnosticsAudit 'Microsoft.Authorization/policyAssignments@2024-04-01' = if (assignAuditPolicy) {
  name: 'audit-diag-${prefix}'
  properties: {
    displayName: 'Audit missing diagnostic settings (${prefix})'
    description: 'Flags resources in this group that send no diagnostic logs anywhere. Audit only — remediation is a pull request against the template that owns the resource.'
    // Built-in "Audit diagnostic setting for selected resource types", v2.0.1.
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/7f89b1eb-583c-429a-8828-af049802c1d9'
    enforcementMode: 'Default'
    parameters: {
      listOfResourceTypes: {
        value: [
          'Microsoft.Network/azureFirewalls'
          'Microsoft.Network/loadBalancers'
          'Microsoft.Network/bastionHosts'
          'Microsoft.KeyVault/vaults'
          'Microsoft.Sql/servers/databases'
          'Microsoft.App/containerApps'
        ]
      }
    }
  }
}

// ---------------------------------------------------------------------------
// The budget. Three thresholds rather than one: a warning while there is still
// time to act, a serious one, and a forecast alert that fires before the money
// is spent rather than after.
// ---------------------------------------------------------------------------
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: 'budget-${prefix}-monthly'
  properties: {
    category: 'Cost'
    amount: monthlyBudgetUsd
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      actualOver50: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: [alertEmail]
        contactGroups: [actionGroup.id]
      }
      actualOver90: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        thresholdType: 'Actual'
        contactEmails: [alertEmail]
        contactGroups: [actionGroup.id]
      }
      // The one that is actually useful: forecast crosses 100% while there is
      // still a month left to do something about it.
      forecastOver100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: [alertEmail]
        contactGroups: [actionGroup.id]
      }
    }
  }
}

output policyAssignmentId string = assignAuditPolicy ? diagnosticsAudit!.id : 'not assigned — needs Resource Policy Contributor, see assignAuditPolicy'
output budgetName string = budget.name
output basicPlanTable string = useBasicPlanForFirewallLogs ? 'AZFWApplicationRule moved to Basic ($0.50/GB vs $2.76/GB)' : 'All tables left on Analytics'
output tablesLeftOnAnalytics array = ['Syslog', 'Heartbeat']
output whyTablesStayed string = 'L2.3 alert rules query these two, and alert rules cannot read Basic tables.'
