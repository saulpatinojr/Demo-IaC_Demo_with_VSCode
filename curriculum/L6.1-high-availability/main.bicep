// ============================================================================
// L6.1 — High Availability & Redundancy (builds on Levels 1–4)
// Grades the architecture Level 1 built, honestly, against availability zones
// and component redundancy — before spending anything on fixing it.
//
// This chapter deploys a REPORT, not redundancy, and that is deliberate. Every
// zone-redundancy upgrade in this estate belongs to the template that owns the
// resource: the container app's replica count is in labs/L3-containers, the
// load balancer's zones are in labs/L2-web-tier. Adding them from here would
// break the ownership rule the whole curriculum runs on. So L6.1 measures, and
// the fix is a pull request against the right file.
//
// Cost: nothing. Azure Resource Graph and workbooks are free.
//
// Prerequisite: Levels 1-4, and L2.2's availability test for the measured
// half of the picture.
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

// Zone information lives in different properties per resource type, so a
// single query has to normalise before it can grade anything.
var zoneAuditQuery = '''
resources
| where resourceGroup =~ "{RG}"
| extend ZoneState = case(
    isnotnull(zones) and array_length(zones) > 1, "Zone-redundant",
    isnotnull(zones) and array_length(zones) == 1, strcat("Zonal (", tostring(zones[0]), ")"),
    "Not zonal")
| extend Sku = tostring(sku.name)
| project Resource = name, Type = type, ZoneState, Sku, Location = location
| order by ZoneState asc, Type asc
'''

var singlePointsQuery = '''
resources
| where resourceGroup =~ "{RG}"
| where type in~ (
    "microsoft.network/bastionhosts",
    "microsoft.network/azurefirewalls",
    "microsoft.sql/servers/databases",
    "microsoft.app/containerapps")
| extend Risk = case(
    type =~ "microsoft.network/bastionhosts", "Single Basic Bastion — no redundancy at this SKU",
    type =~ "microsoft.network/azurefirewalls", "One firewall instance unless zones are set",
    type =~ "microsoft.sql/servers/databases", "Basic tier cannot be made zone-redundant at all",
    "One replica per region by default")
| project Resource = name, Type = type, Risk
'''

var workbookContent = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '# ${prefix} — redundancy grade\n\nThis page measures. It does not fix anything, because every fix belongs to the template that owns the resource — the container app replica count lives in `labs/L3-containers`, the load balancer zones in `labs/L2-web-tier`. Read the grade, then open a pull request against the right file.\n\nAn honest reading of this estate: **two regions is not the same as surviving the loss of one.**'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: replace('{RG}', resourceGroup().name, zoneAuditQuery)
        size: 0
        title: 'Every resource, graded by zone posture'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        visualization: 'table'
      }
    }
    {
      type: 1
      content: {
        json: '## The four that will not pass\n\nThese are the single points of failure L1.4 left behind. Three of them are cheap to fix and one is not — being able to say which is which is the point of the chapter.'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: replace('{RG}', resourceGroup().name, singlePointsQuery)
        size: 0
        title: 'Known single points of failure'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
        visualization: 'table'
      }
    }
    {
      type: 1
      content: {
        json: '## What the fixes cost\n\n| Fix | Where it lives | Cost |\n|---|---|---|\n| Second container replica per region | `labs/L3-containers` | +$0.054/hr each |\n| Zone-redundant firewall | `labs/L2-web-tier` | no extra charge — zones are free on the same SKU |\n| Zone-redundant load balancer | `labs/L2-web-tier` | no extra charge |\n| Zone-redundant SQL | not possible on Basic | +~$0.25/hr to leave Basic |\n\nThree of the four cost nothing but a redeploy. Spend the fixed budget where it buys the most nines, and decline the database upgrade with evidence.'
      }
    }
  ]
  '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
}

resource redundancyWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'l61-redundancy-grade')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'L6.1 — ${prefix} redundancy grade'
    serializedData: string(workbookContent)
    category: 'workbook'
    sourceId: 'Azure Monitor'
  }
}

output workbookResourceId string = redundancyWorkbook.id
output costOfThisChapter string = '$0.00/hr — Resource Graph and workbooks are free. This chapter measures; it does not buy anything.'
output freeFixes array = [
  'Zone-redundant Azure Firewall — same SKU, set zones, no extra charge'
  'Zone-redundant load balancer — same SKU, no extra charge'
]
output paidFixes array = [
  'Second container replica per region — $0.054/hr each'
  'Zone-redundant SQL — requires leaving Basic, about +$0.25/hr'
]
output ownershipRule string = 'Every fix belongs to the template that owns the resource. This chapter deliberately changes nothing, so the redundancy upgrade arrives as a reviewed pull request against labs/, not as a side effect of a Level 6 deployment.'
