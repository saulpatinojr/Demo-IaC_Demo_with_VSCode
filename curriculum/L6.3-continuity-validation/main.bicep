// ============================================================================
// L6.3 — Business Continuity & Validation (builds on L6.1 and L6.2)
// Proves the recovery capability instead of asserting it: an availability SLO
// alert on the L2.2 web test, and a drill-reporting workbook that turns each
// exercise into evidence with numbers in it.
//
// The closing chapter of the curriculum, and the one that ties the whole thing
// together. Every query on the workbook reads data a previous level collected:
// availability from L2.2, backup job history from L4.3, replication health
// from L6.2. Nothing new is instrumented, because the point is that a
// well-instrumented estate can already answer these questions.
//
// Cost: nothing in steady state. Drills are event costs -- a test failover
// bills the temporary VM and disks while they exist (~$0.05/hr per VM), and
// Azure Chaos Studio is $0.10 per action-minute, so a ten-minute experiment is
// about a dollar. Budget $2-5 per full drill and delete everything after.
//
// Prerequisite: L6.1 and L6.2. L2.2 for the availability test the SLO alert
// reads, L4.3 for the backup job history.
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace the drill evidence is queried from. Defaults to the one every level has been filling.')
param workspaceName string = 'log-${prefix}-l3'

@description('Action group the SLO breach notifies. Defaults to the one L2.3 created.')
param actionGroupName string = 'ag-${prefix}-oncall'

@description('Availability target, as a percentage over the evaluation window. 99.0 is deliberately modest — an SLO you meet every week teaches nothing, and one you can never meet gets ignored.')
@minValue(90)
@maxValue(100)
param availabilityTargetPercent int = 99

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' existing = {
  name: actionGroupName
}

// The SLO alert. Not "is it up right now" — L2.3 already answers that — but
// "did we meet the number we promised over the window", which is the question
// a business continuity conversation actually turns on.
resource sloBreachAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${prefix}-availability-slo'
  location: location
  properties: {
    displayName: 'Availability below the SLO over the last 24 hours'
    description: 'Measured from the L2.2 availability test. This is a service-level question, not an outage alert — it can fire when nothing is currently broken, which is the point.'
    severity: 2
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: 'PT1H'
    windowSize: 'P1D'
    criteria: {
      allOf: [
        {
          query: 'AppAvailabilityResults\n| where TimeGenerated > ago(24h)\n| summarize Total = count(), Successful = countif(Success == true)\n| extend AvailabilityPercent = round(100.0 * Successful / Total, 2)\n| where Total > 0 and AvailabilityPercent < ${availabilityTargetPercent}'
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

var drillWorkbook = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '# ${prefix} — continuity evidence\n\nEvery number on this page comes from data an earlier level already collects. That is the finding: a well-instrumented estate can answer continuity questions without a special project.\n\n**Before a drill,** write down the RTO and RPO you expect. **After it,** put the measured numbers next to them. The gap is the report.'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AppAvailabilityResults\n| where TimeGenerated > ago(30d)\n| summarize Total = count(), Successful = countif(Success == true) by bin(TimeGenerated, 1d), Location\n| extend AvailabilityPercent = round(100.0 * Successful / Total, 2)\n| project TimeGenerated, Location, AvailabilityPercent\n| render timechart'
        size: 0
        title: 'Measured availability by probe location — 30 days'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        visualization: 'timechart'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AddonAzureBackupJobs\n| where TimeGenerated > ago(30d) and JobOperation in ("Backup", "Restore")\n| summarize Jobs = count(), Failed = countif(JobStatus == "Failed"), SlowestMinutes = round(max(JobDurationInSecs) / 60.0, 1) by JobOperation\n| extend SuccessRate = round(100.0 * (Jobs - Failed) / Jobs, 1)'
        size: 0
        title: 'Backup and restore history — the RTO evidence from L4.3'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        visualization: 'table'
      }
    }
    {
      type: 1
      content: {
        json: '## Drill record\n\n| Drill | Target RTO | Measured RTO | Target RPO | Measured RPO | Gap |\n|---|---|---|---|---|---|\n| File-level restore (L4.1) | | | | | |\n| Full VM restore (L4.3) | | | | | |\n| Database point-in-time restore (L4.2) | | | | | |\n| ASR test failover (L6.2) | | | | | |\n| SQL failover group failover (L1.4) | | | | | |\n\nFill this in during the drill, not afterwards from memory. An untested recovery plan is a recovery hope, and the cheapest possible DR posture is an untested one — which is exactly why it is a false saving.'
      }
    }
  ]
  '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
}

resource continuityWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'l63-continuity-evidence')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'L6.3 — ${prefix} continuity evidence'
    serializedData: string(drillWorkbook)
    category: 'workbook'
    sourceId: workspace.id
  }
}

output sloAlertName string = sloBreachAlert.name
output availabilityTarget string = '${string(availabilityTargetPercent)}% over 24 hours, measured from the L2.2 availability test'
output workbookResourceId string = continuityWorkbook.id
output steadyStateCost string = '$0.00/hr. Drills are event costs: a test failover bills the temporary VM and disks while they exist (~$0.05/hr per VM), and Chaos Studio is $0.10 per action-minute. Budget $2-5 per full drill and delete everything afterwards.'
output everyQueryIsInherited string = 'Availability comes from L2.2, backup and restore history from L4.3, replication health from L6.2. This chapter instruments nothing new — a well-instrumented estate can already answer continuity questions.'
output theClosingArgument string = 'Resilience is bought mostly with discipline and only partly with money. Levels 2-6 together add about $0.71/hr; the Azure Firewall from L1.2 alone is $1.25/hr.'
