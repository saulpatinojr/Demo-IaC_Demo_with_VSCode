// ============================================================================
// L5.2 — Detection & Investigation (builds on L5.1)
// Detections that fire on THIS environment's real behaviour, written against
// the data the previous nine chapters collected.
//
// Detection logic is free. You pay for the data, not the queries -- which
// means the right instinct here is to write more rules over less data rather
// than to collect more. Every rule below queries something already flowing.
//
// Entity mapping is the part people skip and then regret: without it an
// incident is a row in a table, and with it Sentinel can pivot to everything
// else that account or host touched.
//
// Prerequisite: L5.1 (nothing can query data that was never connected).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Workspace the rules run against. Defaults to the Sentinel workspace from L5.1.')
param workspaceName string = 'log-${prefix}-l3'

@description('Enable the UEBA-style rule that needs Microsoft Entra ID sign-in data. OFF by default because that connector cannot be enabled from Azure — it needs a directory admin — so the rule would run against an empty table and never fire.')
param includeEntraIdRules bool = false

@description('How far back each scheduled rule looks. Longer windows catch slower attacks and re-scan more data; they do not cost more to execute, but they do interact with retention.')
@allowed(['PT1H', 'PT6H', 'P1D'])
param lookbackWindow string = 'PT6H'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

// --- Rule 1: a Defender alert on a resource that also failed to authenticate.
// This is the point of putting security and operations data in ONE workspace:
// neither table alone says much, and the join is the detection.
resource correlatedSqlAttack 'Microsoft.SecurityInsights/alertRules@2023-02-01' = {
  scope: workspace
  name: guid(workspace.id, 'sql-attack-correlation')
  kind: 'Scheduled'
  properties: {
    displayName: 'SQL brute force with a Defender alert on the same server'
    description: 'Correlates repeated failed SQL authentications from L3.2 auditing with a Defender for Cloud alert on the same resource. Either signal alone is noise; together they are an incident.'
    severity: 'High'
    enabled: true
    query: '''
let window = 6h;
let alerts = SecurityAlert
  | where TimeGenerated > ago(window)
  | extend Resource = tostring(parse_json(ExtendedProperties)["Resource"])
  | project AlertTime = TimeGenerated, AlertName, Resource;
SQLSecurityAuditEvents
| where TimeGenerated > ago(window) and action_name == "DATABASE AUTHENTICATION FAILED"
| summarize Failures = count(), Accounts = make_set(server_principal_name) by _ResourceId
| where Failures > 5
| join kind=leftouter alerts on $left._ResourceId == $right.Resource
| project TimeGenerated = now(), _ResourceId, Failures, Accounts, AlertName
'''
    queryFrequency: 'PT1H'
    queryPeriod: lookbackWindow
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: ['CredentialAccess', 'InitialAccess']
    techniques: ['T1110']
    // Without entity mapping this is a table row. With it, the incident opens
    // with the host and account already pivotable.
    entityMappings: [
      {
        entityType: 'AzureResource'
        fieldMappings: [
          {
            identifier: 'ResourceId'
            columnName: '_ResourceId'
          }
        ]
      }
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'PT5H'
        matchingMethod: 'AllEntities'
      }
    }
  }
}

// --- Rule 2: the firewall started allowing something new.
// Runs against AZFWApplicationRule, which L5.1 moved to the Basic plan --
// so this rule exists partly to prove that a Basic table CAN still be queried
// by a scheduled rule when the query is a simple filter and aggregation.
resource newEgressDestination 'Microsoft.SecurityInsights/alertRules@2023-02-01' = {
  scope: workspace
  name: guid(workspace.id, 'new-egress-destination')
  kind: 'Scheduled'
  properties: {
    displayName: 'Outbound traffic to a destination never seen before'
    description: 'A workload reaching somewhere it has not reached in the previous seven days. High false-positive rate by design — this is a hunting-grade signal promoted to a low-severity rule so the class can practise triage on something that fires.'
    severity: 'Low'
    enabled: true
    query: '''
let known = AZFWApplicationRule
  | where TimeGenerated between (ago(7d) .. ago(1d))
  | summarize by Fqdn;
AZFWApplicationRule
| where TimeGenerated > ago(1d) and Action == "Allow"
| where isnotempty(Fqdn)
| join kind=leftanti known on Fqdn
| summarize Requests = count(), FirstSeen = min(TimeGenerated) by Fqdn, SourceIp
| where Requests > 3
| extend TimeGenerated = FirstSeen
'''
    queryFrequency: 'PT1H'
    queryPeriod: 'P7D'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: ['CommandAndControl', 'Exfiltration']
    entityMappings: [
      {
        entityType: 'IP'
        fieldMappings: [
          {
            identifier: 'Address'
            columnName: 'SourceIp'
          }
        ]
      }
      {
        entityType: 'DNS'
        fieldMappings: [
          {
            identifier: 'DomainName'
            columnName: 'Fqdn'
          }
        ]
      }
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'PT5H'
        matchingMethod: 'AllEntities'
      }
    }
  }
}

// --- Rule 3: needs directory data this lab cannot connect.
// Deployed only when someone with the right role has connected Microsoft Entra
// ID logs. Left off, it would query an empty table and quietly never fire,
// which is worse than not existing.
resource impossibleTravel 'Microsoft.SecurityInsights/alertRules@2023-02-01' = if (includeEntraIdRules) {
  scope: workspace
  name: guid(workspace.id, 'entra-signin-anomaly')
  kind: 'Scheduled'
  properties: {
    displayName: 'Sign-ins to the lab subscription from more than two countries in an hour'
    description: 'Requires the Microsoft Entra ID connector, which a Global Administrator or Security Administrator must enable in the directory. Included so the rule set is complete on paper even when the lab cannot run it.'
    severity: 'Medium'
    enabled: true
    query: '''
SigninLogs
| where TimeGenerated > ago(1h) and ResultType == 0
| summarize Countries = dcount(Location), CountryList = make_set(Location) by UserPrincipalName
| where Countries > 2
| extend TimeGenerated = now()
'''
    queryFrequency: 'PT1H'
    queryPeriod: 'PT1H'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: ['InitialAccess']
    entityMappings: [
      {
        entityType: 'Account'
        fieldMappings: [
          {
            identifier: 'FullName'
            columnName: 'UserPrincipalName'
          }
        ]
      }
    ]
  }
}

output ruleCount int = includeEntraIdRules ? 3 : 2
output rulesDeployed array = includeEntraIdRules
  ? ['SQL brute force correlation', 'New egress destination', 'Entra ID sign-in anomaly']
  : ['SQL brute force correlation', 'New egress destination']
output whyOneWorkspace string = 'Rule 1 joins SecurityAlert to SQLSecurityAuditEvents. Neither table alone is an incident. That join is only possible because every level wrote into the same workspace.'
output executionIsFree string = 'Analytics rules, hunting and investigation carry no charge. You pay for the data, not the queries — so write more rules over less data.'
output blockedRule string = includeEntraIdRules
  ? 'Entra ID rule deployed. It only produces results if a directory admin connected SigninLogs.'
  : 'The Entra ID rule is NOT deployed. Its table would be empty, and a rule that can never fire is worse than no rule — it looks like coverage.'
