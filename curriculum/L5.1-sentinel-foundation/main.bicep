// ============================================================================
// L5.1 — Sentinel Foundation (builds on Levels 1–4)
// Enables Microsoft Sentinel on the workspace this curriculum has been filling
// since L2.1, and connects the sources that are FREE before anything paid.
//
// Read this before you deploy, because it is the largest cost decision in the
// curriculum and it is a SELECTION decision, not a purchase:
//
//   * Sentinel bills on everything in the workspace it is enabled on. The
//     operations data from Level 2 is already there, so enabling Sentinel here
//     applies Sentinel analysis charges to it as well. That is why L2.4's
//     table-plan discipline matters now rather than then.
//   * The 31-day free trial waives BOTH Log Analytics ingestion and Sentinel
//     analysis for the first 10 GB/day. This estate fits inside that, which
//     makes Level 5 nearly free -- if the class runs inside the window.
//   * Defender for Cloud alerts (SecurityAlert), exported by L3.3, are a FREE
//     data source. The security work is already paid for.
//
// WHAT THIS TEMPLATE CANNOT DO: connect Microsoft Entra ID sign-in and audit
// logs. That connector is granted in the DIRECTORY by a Global Administrator
// or Security Administrator, not in Azure by a resource-group Contributor.
// It is also PAID data. Both facts belong in the same conversation.
//
// Prerequisite: Levels 1-4. Sentinel Contributor on the workspace.
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Workspace Sentinel is enabled on. Defaults to the one L2.1 filled — deliberately, so Level 5 inherits the estate rather than starting again.')
param workspaceName string = 'log-${prefix}-l3'

@description('Connect Microsoft Defender for Cloud alerts. FREE, and the reason L3.3 exported them. Needs Sentinel Contributor plus read on the subscription.')
param connectDefenderForCloud bool = true

@description('Move the highest-volume operational table to the Auxiliary plan when Sentinel is enabled. Sentinel charges analysis on everything in the workspace, so a table nothing detects on is pure cost — this is the L2.4 lesson arriving with a bigger bill attached.')
param demoteVerboseTableOnOnboard bool = true

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// Enabling Sentinel is a single resource on the workspace. Everything else in
// Level 5 is content that sits on top of it.
resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  scope: workspace
  name: 'default'
  properties: {}
}

// Free connector. The dataTypes block is the part worth reading: connectors are
// not all-or-nothing, and choosing types is how you keep a free source free.
resource defenderConnector 'Microsoft.SecurityInsights/dataConnectors@2023-02-01' = if (connectDefenderForCloud) {
  scope: workspace
  name: guid(workspace.id, 'defender-for-cloud')
  kind: 'AzureSecurityCenter'
  properties: {
    subscriptionId: subscription().subscriptionId
    dataTypes: {
      alerts: {
        state: 'Enabled'
      }
    }
  }
  dependsOn: [
    sentinel
  ]
}

// Sentinel changes the economics of a table that was merely verbose. Auxiliary
// is $0.05/GB against Analytics' $2.76, and Sentinel analysis on top of that is
// $4.76/GB you would otherwise pay for firewall chatter nothing detects on.
resource demoteTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = if (demoteVerboseTableOnOnboard) {
  parent: workspace
  name: 'AZFWNetworkRule'
  properties: {
    plan: 'Basic'
    totalRetentionInDays: 180
  }
  dependsOn: [
    sentinel
  ]
}

output sentinelEnabledOn string = workspaceName
output freeConnectors array = connectDefenderForCloud ? ['Microsoft Defender for Cloud (SecurityAlert)'] : []
output freeDataSources array = [
  'AzureActivity — free, already flowing from L2.1'
  'SecurityAlert / SecurityIncident — free, exported by L3.3'
  'Microsoft Sentinel Health — free'
]
output paidAndBlocked string = 'Microsoft Entra ID sign-in and audit logs are PAID data AND need a Global Administrator or Security Administrator in the directory. A resource-group Contributor cannot connect them. Arrange it before the class, not during it.'
output costModel string = 'Analytics tier: $2.76/GB Log Analytics ingestion + $4.76/GB Sentinel analysis = about $7.52/GB. Free trial waives both for the first 10 GB/day for 31 days.'
output whatToWatch string = 'Re-run L2.4 Usage query tomorrow. Anything still on the Analytics plan is now costing $7.52/GB, not $2.76 — that difference is the whole of Level 5 cost management.'
