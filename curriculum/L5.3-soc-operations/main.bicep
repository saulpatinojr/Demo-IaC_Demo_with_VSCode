// ============================================================================
// L5.3 — SOC Operations & Automation (builds on L5.2)
// Operating the SIEM: automation rules that triage before a human sees an
// incident, a playbook for the response, and a closing cost review.
//
// Same connector constraint as L3.3, and for the same reason: a playbook that
// posts to Teams or opens a ticket needs an API connection, and an API
// connection needs an interactive OAuth consent no deployment can perform. The
// playbook here is HTTP-triggered and self-contained so it works the first
// time; adding a connector afterwards is a deliberate, consented step.
//
// Automation rules, playbook triggers, workbooks and incident management are
// all free. Logic Apps consumption is fractions of a cent per action. The only
// meaningful cost in this chapter is the one you REMOVE in the closing review.
//
// Prerequisite: L5.2 (incidents to automate).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Workspace Sentinel runs on. Defaults to the one from L5.1.')
param workspaceName string = 'log-${prefix}-l3'

@description('Automatically close low-severity incidents older than the grace period. This is a governance decision disguised as a convenience — an auto-closed incident is one nobody looked at, and the class should argue about it before enabling it.')
param autoCloseLowSeverity bool = false

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// ---------------------------------------------------------------------------
// The playbook. No connectors, so it deploys and runs first time.
// ---------------------------------------------------------------------------
resource playbook 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'logic-${prefix}-incident-enrich'
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        When_an_incident_is_created: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                Title: { type: 'string' }
                Severity: { type: 'string' }
                Entities: { type: 'array' }
                IncidentNumber: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        // The first thirty seconds of triage, written down once instead of
        // remembered differently by each analyst.
        Enrich: {
          type: 'Compose'
          runAfter: {}
          inputs: {
            incident: '@triggerBody()?[\'IncidentNumber\']'
            title: '@triggerBody()?[\'Title\']'
            severity: '@triggerBody()?[\'Severity\']'
            entities: '@triggerBody()?[\'Entities\']'
            firstQuestions: [
              'Is the affected resource part of this lab, or something else in the subscription?'
              'Does the Level 2 workspace show an operational explanation in the same window?'
              'Did a Level 4 backup job run successfully after the activity?'
            ]
          }
        }
        Respond: {
          type: 'Response'
          kind: 'Http'
          runAfter: {
            Enrich: ['Succeeded']
          }
          inputs: {
            statusCode: 200
            body: '@outputs(\'Enrich\')'
          }
        }
      }
      outputs: {}
    }
  }
}

// ---------------------------------------------------------------------------
// Automation rules. These run BEFORE a human sees the incident, which is what
// makes them powerful and what makes a bad one dangerous.
// ---------------------------------------------------------------------------
resource tagAndAssign 'Microsoft.SecurityInsights/automationRules@2023-02-01' = {
  scope: workspace
  name: guid(workspace.id, 'triage-high-severity')
  properties: {
    displayName: 'Tag and prioritise high-severity incidents'
    order: 1
    triggeringLogic: {
      isEnabled: true
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentSeverity'
            operator: 'Equals'
            propertyValues: ['High']
          }
        }
      ]
    }
    actions: [
      {
        order: 1
        actionType: 'ModifyProperties'
        actionConfiguration: {
          severity: 'High'
          status: 'Active'
          labels: [
            { labelName: 'lab-${prefix}' }
            { labelName: 'auto-triaged' }
          ]
        }
      }
    ]
  }
}

// Off by default, and the parameter description says why. Auto-closing is the
// automation rule most likely to be regretted.
resource autoClose 'Microsoft.SecurityInsights/automationRules@2023-02-01' = if (autoCloseLowSeverity) {
  scope: workspace
  name: guid(workspace.id, 'auto-close-informational')
  properties: {
    displayName: 'Close informational incidents automatically'
    order: 2
    triggeringLogic: {
      isEnabled: true
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentSeverity'
            operator: 'Equals'
            propertyValues: ['Informational']
          }
        }
      ]
    }
    actions: [
      {
        order: 1
        actionType: 'ModifyProperties'
        actionConfiguration: {
          status: 'Closed'
          classification: 'BenignPositive'
          classificationComment: 'Auto-closed by the L5.3 automation rule. If this classification is wrong, the rule is wrong — change the rule, not the incident.'
          classificationReason: 'SuspiciousButExpected'
        }
      }
    ]
  }
}

output playbookResourceId string = playbook.id
output automationRuleCount int = autoCloseLowSeverity ? 2 : 1
output playbookHasNoConnectors string = 'HTTP-triggered and self-contained, so it works on first run. A Teams or ticketing action needs an API connection and an interactive OAuth consent — see the permissions box on the wiki page for who can grant it.'
output autoCloseWarning string = autoCloseLowSeverity
  ? 'Auto-close is ON. Every informational incident is now closed without a human reading it. Review the closed queue weekly or this rule is hiding things.'
  : 'Auto-close is OFF. Turn it on only after you have watched the informational queue for a week and can say what is in it.'
output realCostOfASoc string = 'Automation rules, playbook triggers, workbooks and incident management are free. Analyst time is the largest cost in any real SOC and appears nowhere on the Azure bill — which is the argument for automating triage.'
output closingExercise string = 'Re-run the L2.4 Usage query. Every table still on the Analytics plan now costs about $7.52/GB with Sentinel analysis. Turn off one connector you have proved you do not need, and record what it saved.'
