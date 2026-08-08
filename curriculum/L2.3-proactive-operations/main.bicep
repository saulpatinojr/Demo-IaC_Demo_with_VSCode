// ============================================================================
// L2.3 — Proactive Operations (builds on L2.1 and L2.2)
// Stops you having to look. Metric alerts on the VMs, the database and the
// firewall; log alerts on the data L2.1 collects; a Service Health alert for
// the failures that are Azure's fault; and an alert processing rule so a
// maintenance window does not page anyone.
//
// This chapter owns its OWN action group. It does not edit ag-<prefix>-ops,
// the one L1.3 created -- two templates owning one resource means whichever
// deployed last wins, and the next L1.3 redeploy would silently revert this
// chapter's work. Adding a resource is cheap; sharing ownership is not.
//
// Cost: metric alerts are $0.10 per monitored metric per month, log alerts
// $0.50 per rule per month at 15-minute evaluation, activity log alerts and
// processing rules are free. The whole set below is about $2.30/month.
//
// Prerequisite: L2.1 (the data) and L2.2 (the queries these rules came from).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace the log alerts query. Defaults to the one L1.3 created and L2.1 filled.')
param workspaceName string = 'log-${prefix}-l3'

@description('Where alerts go. Same address you used in L1.3 unless you want a second inbox.')
param alertEmail string = 'you@example.com'

@description('Second address, so a signal does not die because one person is on holiday. Leave empty for a single receiver.')
param secondaryAlertEmail string = ''

@description('Set false if you tore down L1.2 — its firewall alerts are then skipped.')
param includeWebTier bool = true

@description('Evaluation frequency for the log alerts. PT15M is $0.50/rule/month; PT5M is three times that for signals that rarely need the extra ten minutes.')
@allowed(['PT5M', 'PT15M'])
param logAlertFrequency string = 'PT15M'

@description('Create the alert processing rule that suppresses everything during the nightly maintenance window. Free, and the point of the exercise — but it does mean real alerts are swallowed in that hour.')
param enableMaintenanceSuppression bool = true

var suffix = take(uniqueString(subscription().id, prefix), 6)

var vmNames = union(
  ['vm-${prefix}-test'],
  includeWebTier ? ['vm-${prefix}-web0', 'vm-${prefix}-web1', 'vm-${prefix}-web2'] : []
)

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [
  for name in vmNames: {
    name: name
  }
]

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' existing = {
  name: 'sql-${prefix}-${suffix}/sqldb-${prefix}-app'
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' existing = if (includeWebTier) {
  name: 'afw-${prefix}-hub'
}

// ---------------------------------------------------------------------------
// Where alerts go. Two receivers, because a notification path with one person
// on it is not a notification path.
// ---------------------------------------------------------------------------
var emailReceivers = union(
  [
    {
      name: 'onCallPrimary'
      emailAddress: alertEmail
      useCommonAlertSchema: true
    }
  ],
  empty(secondaryAlertEmail)
    ? []
    : [
        {
          name: 'onCallSecondary'
          emailAddress: secondaryAlertEmail
          useCommonAlertSchema: true
        }
      ]
)

module onCallGroup 'br/public:avm/res/insights/action-group:0.8.0' = {
  name: 'l23-action-group'
  params: {
    name: 'ag-${prefix}-oncall'
    groupShortName: 'oncall'
    emailReceivers: emailReceivers
  }
}

// ---------------------------------------------------------------------------
// Metric alerts. These read the free platform metric store, so they add no
// ingestion — the only charge is the rule itself, per monitored resource.
// ---------------------------------------------------------------------------

// One rule across every VM rather than one rule per VM. Multi-resource alerts
// are why the scope is an array: adding a VM later needs no new rule, and the
// bill grows by one monitored metric instead of one rule.
module vmCpuAlert 'br/public:avm/res/insights/metric-alert:0.4.1' = {
  name: 'l23-vm-cpu-alert'
  params: {
    name: 'alert-${prefix}-vm-cpu'
    scopes: [for (name, i) in vmNames: vms[i].id]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allof: [
        {
          name: 'HighCpu'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [onCallGroup.outputs.resourceId]
  }
}

// Dynamic threshold, because "what is normal for this database" is not a number
// anyone in this class knows. Same price as a static one.
module sqlDtuAlert 'br/public:avm/res/insights/metric-alert:0.4.1' = {
  name: 'l23-sql-dtu-alert'
  params: {
    name: 'alert-${prefix}-sql-dtu'
    scopes: [sqlDatabase.id]
    targetResourceType: 'Microsoft.Sql/servers/databases'
    targetResourceRegion: location
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allof: [
        {
          name: 'DtuAnomaly'
          metricName: 'dtu_consumption_percent'
          metricNamespace: 'Microsoft.Sql/servers/databases'
          operator: 'GreaterThan'
          alertSensitivity: 'Medium'
          timeAggregation: 'Average'
          criterionType: 'DynamicThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 3
          }
        }
      ]
    }
    actions: [onCallGroup.outputs.resourceId]
  }
}

// SNAT port exhaustion is the failure that looks like "the app is randomly
// broken" and is invisible without this metric.
module firewallSnatAlert 'br/public:avm/res/insights/metric-alert:0.4.1' = if (includeWebTier) {
  name: 'l23-fw-snat-alert'
  params: {
    name: 'alert-${prefix}-fw-snat'
    scopes: [firewall!.id]
    targetResourceType: 'Microsoft.Network/azureFirewalls'
    targetResourceRegion: location
    severity: 1
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allof: [
        {
          name: 'SnatPortsHigh'
          metricName: 'SNATPortUtilization'
          metricNamespace: 'Microsoft.Network/azureFirewalls'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [onCallGroup.outputs.resourceId]
  }
}

// ---------------------------------------------------------------------------
// Log alerts. These query the data L2.1 collects, which is why they can catch
// things no platform metric exposes — a VM that stopped reporting at all, or a
// pattern across several resources at once.
// ---------------------------------------------------------------------------
resource heartbeatAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${prefix}-vm-silent'
  location: location
  properties: {
    displayName: 'A VM stopped reporting'
    description: 'No heartbeat from a monitored VM in the last 15 minutes. A metric alert cannot see this: a VM that is gone emits no metrics to threshold.'
    severity: 1
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: logAlertFrequency
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'Heartbeat\n| summarize LastSeen = max(TimeGenerated) by Computer\n| where LastSeen < ago(15m)'
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
      actionGroups: [onCallGroup.outputs.resourceId]
    }
  }
}

resource syslogErrorAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${prefix}-syslog-errors'
  location: location
  properties: {
    displayName: 'Syslog errors spiking'
    description: 'More than 20 error-or-worse syslog events across the estate in 15 minutes.'
    severity: 3
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: logAlertFrequency
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'Syslog\n| where SeverityLevel in ("err", "crit", "alert", "emerg")'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 20
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [onCallGroup.outputs.resourceId]
    }
  }
}

// ---------------------------------------------------------------------------
// Service Health. Free, subscription-scoped, and the only alert here that
// fires for something you cannot fix — which is exactly why you want to know
// before you spend an hour debugging your own template.
// ---------------------------------------------------------------------------
resource serviceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-${prefix}-service-health'
  location: 'global'
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: onCallGroup.outputs.resourceId
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Suppression. A maintenance window that pages everyone teaches people to
// ignore the pager, which is worse than having no pager. Free.
// ---------------------------------------------------------------------------
resource maintenanceSuppression 'Microsoft.AlertsManagement/actionRules@2021-08-08' = if (enableMaintenanceSuppression) {
  name: 'apr-${prefix}-maintenance-window'
  location: 'global'
  properties: {
    description: 'Suppress every alert in this resource group between 02:00 and 03:00 UTC nightly.'
    enabled: true
    scopes: [resourceGroup().id]
    actions: [
      {
        actionType: 'RemoveAllActionGroups'
      }
    ]
    schedule: {
      timeZone: 'UTC'
      recurrences: [
        {
          recurrenceType: 'Daily'
          startTime: '02:00:00'
          endTime: '03:00:00'
        }
      ]
    }
  }
}

output actionGroupResourceId string = onCallGroup.outputs.resourceId
output metricAlertCount int = includeWebTier ? 3 : 2
output logAlertCount int = 2
// Metric alerts bill per monitored resource, log alerts per rule.
output monthlyAlertCostBasis string = '${string(length(vmNames) + (includeWebTier ? 2 : 1))} monitored metrics at $0.10/month, 2 log rules at ${logAlertFrequency == 'PT15M' ? '$0.50' : '$1.50'}/month. Service Health and the processing rule are free.'
