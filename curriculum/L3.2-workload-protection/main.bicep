// ============================================================================
// L3.2 — Workload Protection (builds on L3.1)
// Turns on the protection a resource-group Contributor genuinely can: Defender
// for SQL at server scope, SQL auditing into the Level 2 workspace, and
// just-in-time VM access.
//
// The split from L3.1 holds. Subscription-wide Defender PLANS are the
// instructor's (scripts/admin/Enable-DefenderPlans.ps1); everything here is
// per-resource and yours. Two consequences worth reading before you deploy:
//
//   * Enabling securityAlertPolicies on a SQL server turns on Defender for SQL
//     FOR THAT SERVER and bills $0.0202/instance/hr (~$14.72/month) whether or
//     not the subscription plan is on. Two servers after L1.4, so ~$0.04/hr.
//   * Just-in-time access requires Defender for Servers PLAN 2 on the
//     subscription. It is off by default here because P1 is the cheaper
//     default in the instructor script, and deploying a JIT policy without P2
//     fails. Turn it on once the plan is.
//
// Prerequisite: L3.1 (you should know what the recommendations say first),
// L1.3 and L1.4 (the SQL servers), L2.1 (the workspace auditing writes to).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace SQL audit events are written to. Defaults to the one L1.3 created and L2.1 filled.')
param workspaceName string = 'log-${prefix}-l3'

@description('Where Defender for SQL alerts are emailed.')
param alertEmail string = 'you@example.com'

@description('L1.4 deployed a second-region SQL server. Set false if you stopped at L1.3 — protecting a server that does not exist fails the deployment.')
param includeSecondaryRegion bool = true

@description('Deploy the just-in-time VM access policy. OFF by default: JIT requires Defender for Servers PLAN 2 on the subscription, and the instructor script defaults to the cheaper Plan 1. Turn it on only after someone has enabled P2, or the deployment fails.')
param enableJitAccess bool = false

@description('Set false if you tore down L1.2 — its three web VMs are then left out of the JIT policy.')
param includeWebTier bool = true

@description('How long a just-in-time access request stays open. PT3H is the Azure default; shorter is better and costs nothing.')
@allowed(['PT1H', 'PT3H', 'PT8H'])
param jitMaxRequestDuration string = 'PT3H'

var suffix = take(uniqueString(subscription().id, prefix), 6)
var primarySqlServerName = 'sql-${prefix}-${suffix}'
var secondarySqlServerName = 'sql-${prefix}-${suffix}-dr'

var vmNames = union(
  ['vm-${prefix}-test'],
  includeWebTier ? ['vm-${prefix}-web0', 'vm-${prefix}-web1', 'vm-${prefix}-web2'] : []
)

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource primarySqlServer 'Microsoft.Sql/servers@2023-08-01' existing = {
  name: primarySqlServerName
}

resource secondarySqlServer 'Microsoft.Sql/servers@2023-08-01' existing = if (includeSecondaryRegion) {
  name: secondarySqlServerName
}

// ---------------------------------------------------------------------------
// Defender for SQL, per server. This is resource-level enablement: it works
// whether or not the subscription plan is on, and it bills either way.
// ---------------------------------------------------------------------------
resource primarySqlDefender 'Microsoft.Sql/servers/securityAlertPolicies@2023-08-01' = {
  parent: primarySqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
    emailAccountAdmins: false
    emailAddresses: [alertEmail]
    retentionDays: 30
    // Nothing is suppressed. A lab that starts with exclusions teaches the
    // wrong reflex; you disable a detection after it has proved noisy, not
    // before you have seen it.
    disabledAlerts: []
  }
}

resource secondarySqlDefender 'Microsoft.Sql/servers/securityAlertPolicies@2023-08-01' = if (includeSecondaryRegion) {
  parent: secondarySqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
    emailAccountAdmins: false
    emailAddresses: [alertEmail]
    retentionDays: 30
    disabledAlerts: []
  }
}

// ---------------------------------------------------------------------------
// SQL auditing into the Level 2 workspace.
//
// isAzureMonitorTargetEnabled on its own sends NOTHING. The audit stream only
// moves once a diagnostic setting on the server's `master` database selects
// the SQLSecurityAuditEvents category — the pair is required, and forgetting
// the second half is the most common reason a SQL audit log is silently empty.
// ---------------------------------------------------------------------------
resource primarySqlAuditing 'Microsoft.Sql/servers/auditingSettings@2023-08-01' = {
  parent: primarySqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
  }
}

resource primaryMasterDb 'Microsoft.Sql/servers/databases@2023-08-01' existing = {
  parent: primarySqlServer
  name: 'master'
}

resource primaryAuditDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'audit-to-workspace'
  scope: primaryMasterDb
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
    ]
  }
  dependsOn: [
    primarySqlAuditing
  ]
}

// ---------------------------------------------------------------------------
// Just-in-time VM access. Closes management ports until someone asks, with an
// expiry — which is what replaces "leave 22 open to the office range and hope".
// Requires Defender for Servers Plan 2 on the subscription.
// ---------------------------------------------------------------------------
resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [
  for name in vmNames: {
    name: name
  }
]

resource jitPolicy 'Microsoft.Security/locations/jitNetworkAccessPolicies@2020-01-01' = if (enableJitAccess) {
  name: '${location}/default'
  kind: 'Basic'
  properties: {
    virtualMachines: [
      for (name, i) in vmNames: {
        id: vms[i].id
        ports: [
          {
            number: 22
            protocol: '*'
            // Deliberately not '*'. A JIT policy that opens the port to the
            // whole internet on request has moved the problem, not solved it.
            allowedSourceAddressPrefix: 'AzureLoadBalancer'
            maxRequestAccessDuration: jitMaxRequestDuration
          }
        ]
      }
    ]
  }
}

output sqlServersProtected array = includeSecondaryRegion
  ? [primarySqlServerName, secondarySqlServerName]
  : [primarySqlServerName]
output sqlDefenderHourlyCost string = includeSecondaryRegion
  ? '$0.0403/hr (2 servers x $0.0202) — about $29.44/month'
  : '$0.0202/hr (1 server) — about $14.72/month'
output auditingTarget string = 'SQLSecurityAuditEvents -> ${workspaceName}. Both the auditing setting AND the master-database diagnostic setting are required; either alone sends nothing.'
output jitEnabled bool = enableJitAccess
output jitNote string = enableJitAccess
  ? 'JIT deployed for ${length(vmNames)} VM(s). Requires Defender for Servers Plan 2 to function.'
  : 'JIT skipped. Enable Defender for Servers Plan 2 first (scripts/admin/Enable-DefenderPlans.ps1 -ServersPlan P2), then redeploy with enableJitAccess = true.'
