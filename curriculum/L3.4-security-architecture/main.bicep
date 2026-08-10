// ============================================================================
// L3.4 — Enterprise Security Architecture (builds on L3.1–L3.3)
// The design chapter, made concrete: a Web Application Firewall policy with
// real custom rules, deployed and priced, and DELIBERATELY NOT ATTACHED to
// L1.4's Front Door.
//
// Two reasons it stays detached, and both are the lesson:
//
//   1. Ownership. The Front Door profile belongs to curriculum/L1.4-production-platform. Attaching
//      a security policy from here would make two templates owners of one
//      resource, and the next L1.4 redeploy would quietly drop the
//      association. The same rule that kept L2.3 out of L1.3's action group.
//   2. Money. Managed rule sets -- the OWASP core ruleset, bot protection --
//      require Front Door PREMIUM at $330/month against Standard's $35. That
//      is +$0.40/hr, roughly a quarter of the entire curriculum's running
//      cost, for one feature.
//
// So: custom rules are deployed (they work on Standard and cost almost
// nothing), managed rules are a parameter that prices itself, and attaching is
// a documented manual step with the bill written next to it.
//
// An unattached WAF policy inspects no traffic and bills no request meter.
// That is the point -- you can read, review and cost this design without
// paying for it.
//
// Prerequisite: L3.1–L3.3. L1.4 if you intend to attach it.
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('WAF tier. Standard_AzureFrontDoor supports CUSTOM rules only and matches the Front Door L1.4 deployed. Premium_AzureFrontDoor adds Microsoft-managed rule sets and bot protection — and requires a Front Door Premium profile at $330/month against Standard\'s $35, about +$0.40/hr.')
@allowed(['Standard_AzureFrontDoor', 'Premium_AzureFrontDoor'])
param wafSku string = 'Standard_AzureFrontDoor'

@description('Prevention blocks matching requests; Detection only logs them. Start in Detection on anything carrying real traffic — a rule that looks obviously correct will block something you did not expect.')
@allowed(['Prevention', 'Detection'])
param wafMode string = 'Detection'

@description('Requests per minute per client IP before the rate-limit rule acts. 100 is generous for a lab and tight enough to demonstrate.')
@minValue(10)
@maxValue(10000)
param rateLimitThreshold int = 100

@description('Country codes to block outright, as a demonstration of geo-filtering. Empty by default: geo-blocking is a business decision, not a security default, and blocking the wrong country is how you discover your users.')
param blockedCountryCodes array = []

// Managed rule sets are a Premium feature. Declaring them on a Standard policy
// is rejected at deployment, so the tier decides the shape of the resource.
var isPremium = wafSku == 'Premium_AzureFrontDoor'

var rateLimitRule = {
  name: 'RateLimitPerClientIp'
  priority: 100
  enabledState: 'Enabled'
  ruleType: 'RateLimitRule'
  rateLimitDurationInMinutes: 1
  rateLimitThreshold: rateLimitThreshold
  action: 'Block'
  matchConditions: [
    {
      matchVariable: 'RequestUri'
      operator: 'Any'
      negateCondition: false
      matchValue: []
    }
  ]
}

var geoBlockRule = {
  name: 'BlockListedCountries'
  priority: 200
  enabledState: 'Enabled'
  ruleType: 'MatchRule'
  action: 'Block'
  matchConditions: [
    {
      matchVariable: 'RemoteAddr'
      operator: 'GeoMatch'
      negateCondition: false
      matchValue: blockedCountryCodes
    }
  ]
}

// A cheap, high-signal rule: block requests that arrive with no user agent at
// all. Real browsers and real API clients send one; a lot of opportunistic
// scanning does not.
var emptyUserAgentRule = {
  name: 'BlockEmptyUserAgent'
  priority: 300
  enabledState: 'Enabled'
  ruleType: 'MatchRule'
  action: 'Block'
  matchConditions: [
    {
      matchVariable: 'RequestHeader'
      selector: 'User-Agent'
      operator: 'Equal'
      negateCondition: false
      matchValue: ['']
    }
  ]
}

var customRules = union(
  [rateLimitRule],
  empty(blockedCountryCodes) ? [] : [geoBlockRule],
  [emptyUserAgentRule]
)

resource wafPolicy 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: 'waf${prefix}${uniqueString(resourceGroup().id)}'
  location: 'global'
  sku: {
    name: wafSku
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
      customBlockResponseStatusCode: 403
    }
    customRules: {
      rules: customRules
    }
    // Microsoft-managed rules exist only on Premium. On Standard this must be
    // an empty set, not an omitted property.
    managedRules: {
      managedRuleSets: isPremium
        ? [
            {
              ruleSetType: 'Microsoft_DefaultRuleSet'
              ruleSetVersion: '2.1'
              ruleSetAction: 'Block'
              exclusions: []
              ruleGroupOverrides: []
            }
            {
              ruleSetType: 'Microsoft_BotManagerRuleSet'
              ruleSetVersion: '1.0'
              exclusions: []
              ruleGroupOverrides: []
            }
          ]
        : []
    }
  }
}

output wafPolicyResourceId string = wafPolicy.id
output wafPolicyName string = wafPolicy.name
output mode string = wafMode
output customRuleCount int = length(customRules)
output managedRulesEnabled bool = isPremium
output attachmentStatus string = 'NOT attached to any Front Door. Attaching is a manual step against the profile curriculum/L1.4-production-platform owns — see the wiki page.'
output costIfAttached string = isPremium
  ? 'Front Door Premium base fee $330/month (~$0.4521/hr) versus Standard $35/month (~$0.0479/hr): about +$0.40/hr, plus WAF request meters.'
  : 'Custom rules on Standard add no base fee — you keep paying the $35/month Front Door Standard already costs, plus per-request WAF meters once attached.'
