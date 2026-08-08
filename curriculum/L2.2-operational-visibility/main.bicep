// ============================================================================
// L2.2 — Operational Visibility (builds on L2.1)
// Turns the data L2.1 started collecting into answers: a query library saved
// into the workspace, a workbook that shows the whole estate on one page, and
// an availability test against L1.4's Front Door endpoint.
//
// Queries, workbooks and saved searches are FREE. The only meter in this
// template is the availability test, at $0.0005 per execution — see the
// comment on testFrequencySeconds before you make it more frequent.
//
// Prerequisite: L2.1 deployed (there is nothing to query otherwise), plus
// L1.3 (workspace, Application Insights) and L1.4 (Front Door) from Level 1.
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace the queries run against. Defaults to the one L1.3 created and L2.1 filled.')
param workspaceName string = 'log-${prefix}-l3'

@description('Application Insights component that owns the availability test. Defaults to the one L1.3 created.')
param appInsightsName string = 'appi-${prefix}-l3'

@description('Deploy the availability test against L1.4 Front Door. Turn it off if you never deployed L1.4, or if you want this chapter to cost nothing at all.')
param enableAvailabilityTest bool = true

@description('Seconds between availability test runs, per location. 900 (15 min) by default. Each execution costs $0.0005, so the bill is: (3600 / this) x locations x $0.0005 per hour. At the default with two locations that is about $0.004/hr; at the portal default of 300 seconds and five locations it is $0.03/hr — more than everything else in Level 2 combined.')
@allowed([300, 600, 900])
param testFrequencySeconds int = 900

@description('Azure regions the availability test runs from. Two is enough to tell a real outage from one bad network path; five is the production answer and 2.5x the cost.')
param testLocations array = [
  'us-il-ch1-azr'
  'emea-nl-ams-azr'
]

// uniqueString keeps globally-unique names stable per subscription — same
// expression as L1.3 and L1.4, so the same names resolve here.
var suffix = take(uniqueString(subscription().id, prefix), 6)

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

// ---------------------------------------------------------------------------
// The query library. Saved searches are the cheapest thing in Azure Monitor —
// free, versioned with the template, and they show up in the portal under
// Logs -> Queries where the next person will actually find them.
// ---------------------------------------------------------------------------
var savedQueries = [
  {
    key: 'vm-heartbeat'
    displayName: 'VMs — last heartbeat'
    query: 'Heartbeat\n| summarize LastSeen = max(TimeGenerated) by Computer\n| extend MinutesAgo = datetime_diff("minute", now(), LastSeen)\n| order by MinutesAgo desc'
  }
  {
    key: 'vm-cpu'
    displayName: 'VMs — CPU over time'
    query: 'Perf\n| where ObjectName == "Processor" and CounterName == "% Processor Time"\n| summarize avg(CounterValue) by bin(TimeGenerated, 5m), Computer\n| render timechart'
  }
  {
    key: 'vm-syslog-errors'
    displayName: 'VMs — syslog errors and above'
    query: 'Syslog\n| where SeverityLevel in ("err", "crit", "alert", "emerg")\n| summarize Events = count() by Computer, Facility, SeverityLevel\n| order by Events desc'
  }
  {
    key: 'firewall-verdicts'
    displayName: 'Firewall — allowed vs denied'
    query: 'AZFWNetworkRule\n| summarize Flows = count() by Action, bin(TimeGenerated, 15m)\n| render columnchart'
  }
  {
    key: 'ingestion-cost'
    displayName: 'Cost — GB ingested by table, last 24h'
    query: 'Usage\n| where TimeGenerated > ago(24h) and IsBillable == true\n| summarize GB = sum(Quantity) / 1000 by DataType\n| extend EstimatedDailyUSD = round(GB * 2.76, 2)\n| order by GB desc'
  }
]

resource savedSearches 'Microsoft.OperationalInsights/workspaces/savedSearches@2023-09-01' = [
  for q in savedQueries: {
    parent: workspace
    name: 'l22-${q.key}'
    properties: {
      category: 'L2.2 Operational Visibility'
      displayName: q.displayName
      query: q.query
      version: 2
    }
  }
]

// ---------------------------------------------------------------------------
// The workbook. Built as a Bicep object and serialised with string(), rather
// than pasted in as one escaped JSON blob — this way the queries stay
// readable, and a reviewer can see what changed in a diff.
// ---------------------------------------------------------------------------
var workbookContent = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '# ${prefix} — estate health\n\nEverything on this page comes from the single workspace L1.3 created and L2.1 filled. Nothing here is billed for being looked at; you paid on the way in.'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: savedQueries[0].query
        size: 0
        title: 'VMs — last heartbeat'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        visualization: 'table'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: savedQueries[1].query
        size: 0
        title: 'VMs — CPU over time'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        visualization: 'timechart'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: savedQueries[3].query
        size: 0
        title: 'Firewall — allowed vs denied'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        visualization: 'barchart'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: savedQueries[4].query
        size: 0
        title: 'What this environment is costing to observe'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        visualization: 'table'
      }
    }
  ]
  '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  // Workbook names must be a GUID. Deriving it keeps redeploys idempotent
  // instead of creating a second copy every run.
  name: guid(resourceGroup().id, 'l22-estate-health')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'L2.2 — ${prefix} estate health'
    serializedData: string(workbookContent)
    category: 'workbook'
    sourceId: workspace.id
  }
}

// ---------------------------------------------------------------------------
// Availability test against the global entry point L1.4 built. This is the one
// billed resource in the chapter, and the frequency and location count are the
// entire bill — which is why both are parameters with the arithmetic written
// on them.
// ---------------------------------------------------------------------------
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' existing = if (enableAvailabilityTest) {
  name: 'afd-${prefix}-${suffix}/fde-${prefix}'
}

resource availabilityTest 'Microsoft.Insights/webtests@2022-06-15' = if (enableAvailabilityTest) {
  name: 'webtest-${prefix}-frontdoor'
  location: location
  kind: 'standard'
  // The hidden-link tag is what binds the test to the Application Insights
  // component. Without it the test runs and the portal shows you nothing.
  tags: {
    'hidden-link:${appInsights.id}': 'Resource'
  }
  properties: {
    SyntheticMonitorId: 'webtest-${prefix}-frontdoor'
    Name: '${prefix} Front Door reachable'
    Enabled: true
    Frequency: testFrequencySeconds
    Timeout: 30
    Kind: 'standard'
    RetryEnabled: true
    Locations: [for loc in testLocations: { Id: loc }]
    Request: {
      // The ! is a promise to the compiler that this reference is safe: the
      // resource above carries the same condition as this one, so whenever
      // this line is evaluated, that endpoint exists.
      RequestUrl: 'https://${frontDoorEndpoint!.properties.hostName}'
      HttpVerb: 'GET'
      ParseDependentRequests: false
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

output workbookResourceId string = workbook.id
output savedQueryCount int = length(savedQueries)
output availabilityTestEnabled bool = enableAvailabilityTest
// Printed so the number is on screen at deploy time rather than on the invoice
// three weeks later. Bicep has no floating-point arithmetic, so this reports
// the execution count and leaves the multiplication to you — which is the
// right place for it anyway, because the rate is the thing that changes.
output availabilityTestExecutionsPerHour int = enableAvailabilityTest
  ? (3600 / testFrequencySeconds) * length(testLocations)
  : 0
output availabilityTestCostBasis string = 'Executions per hour x $0.0005 per execution (East US 2 list, Aug 2026).'
