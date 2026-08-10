// ============================================================================
// L2.1 — Monitoring Fundamentals (builds on all of Level 1)
// Points the environment Level 1 deployed at ONE Log Analytics workspace: an
// Azure Monitor Agent and a data collection rule on every VM, and diagnostic
// settings on the firewall, load balancer, Bastion, Key Vault, SQL database
// and container app.
//
// This template deploys no application infrastructure and creates no
// workspace. It REUSES the workspace L1.3 already made (log-<prefix>-l3),
// which is what makes L5 Sentinel possible later without a second workspace
// to reconcile. If you point it somewhere else, use -workspaceName.
//
// Cost note: nothing here has an hourly rate. Everything below bills per GB
// ingested, so the parameters are the price dial — read the comments on
// sendPlatformMetricsToLogs and collectFirewallLogs before turning them on.
//
// Prerequisite: L1.1–L1.4 deployed (same prefix, same resource group).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace everything reports to. Defaults to the one L1.3 created.')
param workspaceName string = 'log-${prefix}-l3'

@description('Set false if you tore down L1.2 to save money — its firewall, load balancer and three web VMs are then skipped.')
param includeWebTier bool = true

@description('How many L1.2 web VMs exist. Ignored when includeWebTier is false.')
@minValue(0)
@maxValue(10)
param webVmCount int = 3

@description('Route platform metrics into Log Analytics as well as the (free) metrics store. Off by default: metrics are free to query in Azure Monitor Metrics and billed per GB once they are copied into logs. Turn it on only for the metrics you want to join against log data.')
param sendPlatformMetricsToLogs bool = false

@description('Collect Azure Firewall network and application rule logs. These are the highest-volume source in the whole estate — that is the point of the exercise, but watch the usage table afterwards.')
param collectFirewallLogs bool = true

// uniqueString keeps globally-unique names (SQL, KV) stable per subscription.
// Same expression as L1.3, so the same names resolve here.
var suffix = take(uniqueString(subscription().id, prefix), 6)

// Every VM in the estate: L1.1's test VM, plus L1.2's web tier if it is still
// standing. AMA and the data collection rule go on all of them.
var vmNames = union(
  ['vm-${prefix}-test'],
  includeWebTier ? map(range(0, webVmCount), i => 'vm-${prefix}-web${i}') : []
)

var diagnosticName = 'diag-to-workspace'

// ---------------------------------------------------------------------------
// The workspace L1.3 created. Referenced, never created — reusing it is the
// architectural decision this chapter is built on.
// ---------------------------------------------------------------------------
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

var metricSettings = sendPlatformMetricsToLogs
  ? [{ category: 'AllMetrics', enabled: true }]
  : []

// ---------------------------------------------------------------------------
// Data collection rule — what the agent gathers, and where it goes.
// This is the "VM insights lite" shape: performance counters every minute and
// syslog at warning and above. Deliberately not the full VM insights set,
// which also ships process and connection data (the Map feature) and is
// several times the volume for a lab that never looks at it.
// ---------------------------------------------------------------------------
module dcr 'br/public:avm/res/insights/data-collection-rule:0.6.0' = {
  name: 'l21-dcr-vm'
  params: {
    name: 'dcr-${prefix}-vm'
    location: location
    dataCollectionRuleProperties: {
      kind: 'Linux'
      description: 'Perf counters and syslog from every Level 1 VM.'
      dataSources: {
        performanceCounters: [
          {
            name: 'perfCounters60s'
            streams: ['Microsoft-Perf']
            samplingFrequencyInSeconds: 60
            counterSpecifiers: [
              '\\Processor(_Total)\\% Processor Time'
              '\\Memory\\% Used Memory'
              '\\Memory\\Available MBytes Memory'
              '\\Logical Disk(_Total)\\% Used Space'
              '\\Network\\Total Bytes Received'
              '\\Network\\Total Bytes Transmitted'
            ]
          }
        ]
        syslog: [
          {
            name: 'syslogWarningAndAbove'
            streams: ['Microsoft-Syslog']
            facilityNames: ['auth', 'authpriv', 'cron', 'daemon', 'kern', 'syslog']
            logLevels: ['Warning', 'Error', 'Critical', 'Alert', 'Emergency']
          }
        ]
      }
      destinations: {
        logAnalytics: [
          {
            name: 'laDestination'
            workspaceResourceId: workspace.id
          }
        ]
      }
      dataFlows: [
        {
          streams: ['Microsoft-Perf', 'Microsoft-Syslog']
          destinations: ['laDestination']
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Azure Monitor Agent on every existing VM, then the association that tells
// each agent which rule to follow. The agent collects nothing on its own — an
// unassociated AMA is the most common "why is there no data?" in Azure Monitor.
// ---------------------------------------------------------------------------
resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [
  for name in vmNames: {
    name: name
  }
]

resource azureMonitorAgent 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [
  for (name, i) in vmNames: {
    parent: vms[i]
    name: 'AzureMonitorLinuxAgent'
    location: location
    properties: {
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorLinuxAgent'
      typeHandlerVersion: '1.33'
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
    }
  }
]

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [
  for (name, i) in vmNames: {
    name: 'dcra-${prefix}-vm'
    scope: vms[i]
    properties: {
      description: 'Associates ${name} with the Level 2 VM data collection rule.'
      dataCollectionRuleId: dcr.outputs.resourceId
    }
    dependsOn: [
      azureMonitorAgent[i]
    ]
  }
]

// ---------------------------------------------------------------------------
// Diagnostic settings on the platform resources. There is no AVM module for
// "apply a diagnostic setting to a resource somebody else created", so these
// are extension resources scoped to an existing reference — which is the
// pattern you want anyway once monitoring is owned by a different template
// from the workload.
// ---------------------------------------------------------------------------

// --- L1.2: firewall and internal load balancer -----------------------------
resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' existing = if (includeWebTier) {
  name: 'afw-${prefix}-hub'
}

// Named categories rather than allLogs on purpose. The firewall emits a dozen
// categories; these two answer "what did it allow and what did it block", and
// they are the ones the L2.2 queries use. allLogs here would multiply the
// level's ingestion bill for data nothing in the curriculum reads.
resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (includeWebTier && collectFirewallLogs) {
  name: diagnosticName
  scope: firewall
  properties: {
    workspaceId: workspace.id
    logs: [
      { category: 'AZFWNetworkRule', enabled: true }
      { category: 'AZFWApplicationRule', enabled: true }
    ]
    metrics: metricSettings
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2024-05-01' existing = if (includeWebTier) {
  name: 'lbi-${prefix}-web'
}

resource loadBalancerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (includeWebTier) {
  name: diagnosticName
  scope: loadBalancer
  properties: {
    workspaceId: workspace.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: metricSettings
  }
}

// --- L1.1: Bastion ---------------------------------------------------------
resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' existing = {
  name: 'bas-${prefix}-hub'
}

resource bastionDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticName
  scope: bastion
  properties: {
    workspaceId: workspace.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: metricSettings
  }
}

// --- L1.3: Key Vault, SQL database, container app --------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: 'kv-${prefix}-${suffix}'
}

// Key Vault audit events are the one category worth arguing over: they are how
// you answer "who read that secret", and L3.3 needs them.
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticName
  scope: keyVault
  properties: {
    workspaceId: workspace.id
    logs: [
      { categoryGroup: 'audit', enabled: true }
    ]
    metrics: metricSettings
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' existing = {
  name: 'sql-${prefix}-${suffix}/sqldb-${prefix}-app'
}

// Basic-tier databases emit far less than the category list suggests, so this
// stays cheap. Errors and timeouts are what L2.3 alerts on.
resource sqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticName
  scope: sqlDatabase
  properties: {
    workspaceId: workspace.id
    logs: [
      { category: 'Errors', enabled: true }
      { category: 'Timeouts', enabled: true }
      { category: 'Blocks', enabled: true }
    ]
    metrics: metricSettings
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: 'ca-${prefix}-web'
}

resource containerAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticName
  scope: containerApp
  properties: {
    workspaceId: workspace.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: metricSettings
  }
}

output workspaceResourceId string = workspace.id
output dataCollectionRuleId string = dcr.outputs.resourceId
output monitoredVmNames array = vmNames
output diagnosticSettingsApplied int = includeWebTier ? (collectFirewallLogs ? 6 : 5) : 4
