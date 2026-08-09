// ============================================================================
// L3.3 — Security Operations (builds on L3.2)
// Gets the alerts L3.2 can now raise out of the portal and into the places
// people actually work: continuous export into the Level 2 workspace, and a
// playbook that runs on every high-severity alert.
//
// This is also the chapter where the SecurityAlert and SecurityRecommendation
// tables stop being empty. L3.1's workbook had to use Azure Resource Graph
// precisely because nothing was exporting yet -- from here on, security data
// is queryable next to the firewall logs that might explain it, and Level 5
// inherits a workspace that already has it.
//
// The playbook deliberately has NO API connections. A Logic App that posts to
// Teams or sends mail needs an API connection, and an API connection needs an
// interactive OAuth consent that no deployment can perform for you -- it would
// deploy green and then fail on first run. This one is HTTP-triggered and
// self-contained, so it demonstrates the wiring and works the first time.
//
// Cost: continuous export is free as a feature; you pay for what it ingests
// (~$2.76/GB, assume ~0.25 GB/day for this estate). Logic Apps consumption is
// fractions of a cent per action.
//
// Prerequisite: L3.2 (no alerts without protection), L2.1 (the workspace),
// L2.3 (the action group).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace security findings are exported to. Defaults to the one L2.1 filled.')
param workspaceName string = 'log-${prefix}-l3'

@description('Export security recommendations as well as alerts. Recommendations are far higher volume than alerts and mostly restate what the L3.1 workbook already shows from Resource Graph — so this is off by default. Turn it on when you want the compliance history over time, and expect the ingestion to show up in L2.4\'s Usage query.')
param exportRecommendations bool = false

@description('Minimum alert severity to export. Low includes informational noise that is useful for a demo and expensive at scale.')
@allowed(['High', 'Medium', 'Low'])
param minimumAlertSeverity string = 'Medium'

var severityList = minimumAlertSeverity == 'Low'
  ? ['High', 'Medium', 'Low']
  : (minimumAlertSeverity == 'Medium' ? ['High', 'Medium'] : ['High'])

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// ---------------------------------------------------------------------------
// The playbook. HTTP-triggered, no connectors, no consent screen. It parses
// the alert Defender hands it and returns a structured summary -- the point is
// the wiring, and the shape of what arrives, not the notification itself.
// ---------------------------------------------------------------------------
resource playbook 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'logic-${prefix}-alert-triage'
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        When_a_security_alert_arrives: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                AlertDisplayName: { type: 'string' }
                Alertseverity: { type: 'string' }
                CompromisedEntity: { type: 'string' }
                Description: { type: 'string' }
                TimeGenerated: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        // Everything a responder needs in the first thirty seconds: what, how
        // bad, which resource, and when. Swap this for a Teams or ticketing
        // action once you have created the API connection interactively.
        Build_triage_summary: {
          type: 'Compose'
          runAfter: {}
          inputs: {
            alert: '@triggerBody()?[\'AlertDisplayName\']'
            severity: '@triggerBody()?[\'AlertSeverity\']'
            resource: '@triggerBody()?[\'CompromisedEntity\']'
            observedAt: '@triggerBody()?[\'TimeGenerated\']'
            runbook: 'Confirm the resource is in scope for this lab, then check SecurityAlert in the workspace for the surrounding activity.'
          }
        }
        Respond: {
          type: 'Response'
          kind: 'Http'
          runAfter: {
            Build_triage_summary: ['Succeeded']
          }
          inputs: {
            statusCode: 200
            body: '@outputs(\'Build_triage_summary\')'
          }
        }
      }
      outputs: {}
    }
  }
}

// ---------------------------------------------------------------------------
// Continuous export. One automation, two destinations: the workspace so the
// data is queryable and retained, and the playbook so something happens
// without a human watching the portal.
//
// listCallbackUrl is how the automation learns the playbook's trigger URL.
// Hardcoding it would break the moment the workflow is redeployed.
// ---------------------------------------------------------------------------
var alertSource = {
  eventSource: 'Alerts'
  ruleSets: [
    {
      rules: [
        {
          propertyJPath: 'Severity'
          propertyType: 'String'
          expectedValue: severityList[0]
          operator: 'Contains'
        }
      ]
    }
  ]
}

var recommendationSource = {
  eventSource: 'Assessments'
  ruleSets: []
}

resource securityExport 'Microsoft.Security/automations@2019-01-01-preview' = {
  name: 'export-${prefix}-security'
  location: location
  properties: {
    description: 'Sends Defender for Cloud findings to the Level 2 workspace and the triage playbook.'
    isEnabled: true
    scopes: [
      {
        description: 'This lab resource group only. Exporting the whole subscription is an instructor decision with an instructor-sized bill.'
        scopePath: resourceGroup().id
      }
    ]
    sources: exportRecommendations ? [alertSource, recommendationSource] : [alertSource]
    actions: [
      {
        actionType: 'Workspace'
        workspaceResourceId: workspace.id
      }
      {
        actionType: 'LogicApp'
        logicAppResourceId: playbook.id
        uri: listCallbackUrl('${playbook.id}/triggers/When_a_security_alert_arrives', '2019-05-01').value
      }
    ]
  }
}

output playbookResourceId string = playbook.id
output exportName string = securityExport.name
output exportedSeverities array = severityList
output tablesThatWillFill array = exportRecommendations
  ? ['SecurityAlert', 'SecurityRecommendation']
  : ['SecurityAlert']
output ingestionNote string = 'Continuous export is free; what it exports is not. Assume ~0.25 GB/day at $2.76/GB for this estate, and check L2.4\'s Usage query tomorrow.'
output sentinelNote string = 'SecurityAlert is a FREE data source in Microsoft Sentinel (L5.1). Exporting it here costs Log Analytics ingestion now and costs nothing extra later.'
