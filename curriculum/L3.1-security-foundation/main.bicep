// ============================================================================
// L3.1 — Security Foundation (builds on Levels 1 and 2)
// Establishes where this environment actually stands, using only free
// capability, before anything is bought.
//
// Deploys a posture workbook driven by Azure Resource Graph rather than by
// Log Analytics. That choice is deliberate and worth understanding: secure
// score and Defender assessments live in ARG's `securityresources` table from
// the moment foundational CSPM is on, which is by default and free. The
// SecurityRecommendation and SecurityAlert tables in Log Analytics stay empty
// until L3.3 turns on continuous export -- so a workspace-driven workbook
// here would render nothing and teach the wrong lesson.
//
// What this template deliberately does NOT do: enable Defender plans.
// Microsoft.Security/pricings is a SUBSCRIPTION-scoped resource, and this lab
// grants Contributor on one resource group. Plans are the instructor's job --
// scripts/admin/Enable-DefenderPlans.ps1. L3.2 then configures the per-resource
// settings a Contributor genuinely can.
//
// Cost: nothing. Foundational CSPM, secure score, recommendations, Azure
// Resource Graph and workbooks are all free.
//
// Prerequisite: Levels 1 and 2 deployed.
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

// Assessments carry a severity but no ordering, so a query cannot sort by risk
// without one. Declaring it here keeps the ranking out of five query strings.
var severityOrder = '''
| extend SeverityRank = case(Severity == "High", 1, Severity == "Medium", 2, 3)
| order by SeverityRank asc, Resources desc
| project-away SeverityRank
'''

var secureScoreQuery = '''
securityresources
| where type == "microsoft.security/securescores"
| extend Current = round(todouble(properties.score.current), 1),
         Max = toint(properties.score.max),
         Percentage = round(todouble(properties.score.percentage) * 100, 1)
| project Subscription = subscriptionId, Current, Max, ["Score %"] = Percentage
'''

var unhealthyByControlQuery = '''
securityresources
| where type == "microsoft.security/assessments"
| extend Status = tostring(properties.status.code),
         Severity = tostring(properties.metadata.severity),
         Recommendation = tostring(properties.displayName)
| where Status == "Unhealthy"
| summarize Resources = count() by Recommendation, Severity
'''

var unhealthyResourcesQuery = '''
securityresources
| where type == "microsoft.security/assessments"
| extend Status = tostring(properties.status.code),
         Severity = tostring(properties.metadata.severity),
         Recommendation = tostring(properties.displayName),
         Target = tostring(properties.resourceDetails.Id)
| where Status == "Unhealthy"
| extend Resource = tostring(split(Target, "/")[-1]),
         ResourceGroup = tostring(split(Target, "/")[4])
| project ResourceGroup, Resource, Recommendation, Severity
| order by ResourceGroup asc, Severity asc
'''

// Which plans are actually on. The answer for a classroom subscription is
// usually "the free ones", and seeing that before L3.2 is the point.
var pricingQuery = '''
securityresources
| where type == "microsoft.security/pricings"
| extend Plan = name, Tier = tostring(properties.pricingTier), SubPlan = tostring(properties.subPlan)
| project Plan, Tier, SubPlan
| order by Tier desc, Plan asc
'''

var workbookContent = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '# ${prefix} — security posture\n\nEverything on this page is **free**. Secure score, recommendations and the Microsoft Cloud Security Benchmark cost nothing on any subscription, and most of the score available to this environment can be earned without enabling a single paid plan.\n\nRead it in this order: the score, then what is dragging it down, then which resource each finding lands on. Only after that does buying a plan make sense.'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: secureScoreQuery
        size: 4
        title: 'Secure score'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        visualization: 'table'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: '${unhealthyByControlQuery}${severityOrder}'
        size: 0
        title: 'Unhealthy recommendations, worst first'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        visualization: 'table'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: unhealthyResourcesQuery
        size: 0
        title: 'Which resource each finding lands on'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        visualization: 'table'
      }
    }
    {
      type: 1
      content: {
        json: '## What is switched on\n\nDefender plans are enabled per **subscription**, not per resource group. If everything below says `Free`, nothing is being paid for and nothing is detecting threats — which is the correct starting point for L3.2, not a fault.'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: pricingQuery
        size: 0
        title: 'Defender plans on this subscription'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        visualization: 'table'
      }
    }
  ]
  '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
}

resource postureWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  // Derived GUID, so a redeploy updates one workbook rather than stacking copies.
  name: guid(resourceGroup().id, 'l31-security-posture')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'L3.1 — ${prefix} security posture'
    serializedData: string(workbookContent)
    category: 'workbook'
    sourceId: 'Azure Monitor'
  }
}

output workbookResourceId string = postureWorkbook.id
output costOfThisChapter string = '$0.00/hr — foundational CSPM, secure score and Resource Graph are free on every subscription.'
output whatIsNotHere string = 'Defender plans are subscription-scoped (Microsoft.Security/pricings) and cannot be enabled with Contributor on one resource group. See scripts/admin/Enable-DefenderPlans.ps1.'
