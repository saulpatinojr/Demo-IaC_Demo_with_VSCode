// ============================================================================
// Lab policy guardrails -- subscription scope
//
// One deployment assigns the full guardrail set to every student resource
// group at once: allowed locations, an allowed-resource-type whitelist, and
// tag inheritance for Owner / Event / Date / Instructor. Six assignments per
// group, each scoped to that group alone.
//
// Set-LabPolicy.ps1 wraps this with the parts a template cannot do --
// reading the class CSV and discovering which resource groups match the
// prefix -- then hands the list here:
//
//     az deployment sub create --location eastus2 \
//       --template-file scripts/admin/lab-policy.bicep \
//       --parameters resourceGroupNames='["rg-techdemo-alice", ...]'
//
// Requires Resource Policy Contributor or Owner: policy assignments sit
// behind Microsoft.Authorization/*/Write, which plain Contributor's
// notActions exclude -- the same wall L2.4 teaches.
// ============================================================================
targetScope = 'subscription'

@description('Resource groups to receive the guardrail set. Set-LabPolicy.ps1 discovers these by prefix.')
param resourceGroupNames array

@description('Regions deployments may target. BOTH defaults are required: L1.1-L1.3 deploy to eastus2, but L1.4 deploys its failover stack to westus2 -- the default of secondaryLocation in curriculum/L1.4-production-platform/main.bicep. Restricting this to eastus2 alone makes L1.4 undeployable.')
param allowedLocations array = ['eastus2', 'westus2']

@description('Resource-group tags each resource inherits.')
param tagsToInherit array = ['Owner', 'Event', 'Date', 'Instructor']

// The "Allowed resource types" policy is a DENY policy that evaluates child
// resources as well as top-level ones, so every child type an AVM module
// creates has to appear here or the student's deployment fails with an
// opaque policy error. Two consequences worth knowing before you edit:
//   * Child types use the full nested path. 'Microsoft.Network/
//     virtualNetworks/virtualNetworkPeerings' is real; 'Microsoft.Network/
//     virtualNetworkPeerings' is not, and an entry that names no real type
//     silently allows nothing.
//   * Bumping an AVM module version can introduce new child types. If
//     students hit policy denials after a template change, re-derive this
//     list rather than guessing:
//       az deployment group what-if -g <rg> -f curriculum/L1.1-core-deployment/main.bicep
@description('Resource types the lab may deploy -- everything L1.1-L1.4 create, children included.')
param allowedResourceTypes array = [
  // Networking -- L1.1 (hub/spoke, Bastion, peering)
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/virtualNetworks/subnets'
  'Microsoft.Network/virtualNetworks/virtualNetworkPeerings'
  'Microsoft.Network/networkInterfaces'
  'Microsoft.Network/networkSecurityGroups'
  'Microsoft.Network/publicIPAddresses'
  'Microsoft.Network/bastionHosts'

  // Networking -- L1.2 (Firewall, route tables, LB)
  'Microsoft.Network/azureFirewalls'
  'Microsoft.Network/firewallPolicies'
  'Microsoft.Network/firewallPolicies/ruleCollectionGroups'
  'Microsoft.Network/routeTables'
  'Microsoft.Network/loadBalancers'
  'Microsoft.Network/loadBalancers/backendAddressPools'
  'Microsoft.Network/loadBalancers/inboundNatRules'
  'Microsoft.Network/publicIPPrefixes'

  // Networking -- L1.3 (private endpoints, DNS)
  'Microsoft.Network/privateDnsZones'
  'Microsoft.Network/privateDnsZones/virtualNetworkLinks'
  'Microsoft.Network/privateDnsZones/A'
  'Microsoft.Network/privateDnsZones/SOA'
  'Microsoft.Network/privateEndpoints'
  'Microsoft.Network/privateEndpoints/privateDnsZoneGroups'

  // Networking -- L1.4 (Front Door Standard; routes hang off the AFD endpoint)
  'Microsoft.Cdn/profiles'
  'Microsoft.Cdn/profiles/afdEndpoints'
  'Microsoft.Cdn/profiles/afdEndpoints/routes'
  'Microsoft.Cdn/profiles/originGroups'
  'Microsoft.Cdn/profiles/originGroups/origins'

  // Compute -- L1.1 / L1.2 VMs
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Compute/virtualMachines/extensions'
  'Microsoft.Compute/disks'

  // Containers -- L1.3
  'Microsoft.App/managedEnvironments'
  'Microsoft.App/containerApps'

  // Data -- L1.3/L1.4 (AVM's sql/server module always writes these child settings)
  'Microsoft.Sql/servers'
  'Microsoft.Sql/servers/databases'
  'Microsoft.Sql/servers/failoverGroups'
  'Microsoft.Sql/servers/firewallRules'
  'Microsoft.Sql/servers/auditingSettings'
  'Microsoft.Sql/servers/securityAlertPolicies'
  'Microsoft.Sql/servers/vulnerabilityAssessments'
  'Microsoft.Sql/servers/connectionPolicies'
  'Microsoft.KeyVault/vaults'
  'Microsoft.KeyVault/vaults/secrets'
  'Microsoft.KeyVault/vaults/accessPolicies'

  // Identity
  'Microsoft.ManagedIdentity/userAssignedIdentities'

  // Monitoring -- L1.3
  'Microsoft.OperationalInsights/workspaces'
  'Microsoft.Insights/components'
  'Microsoft.Insights/metricAlerts'
  'Microsoft.Insights/actionGroups'
  'Microsoft.Insights/diagnosticSettings'

  // ARM / RBAC plumbing
  'Microsoft.Authorization/roleAssignments'
  'Microsoft.Resources/deployments'
]

module rgPolicies 'lab-policy-rg.bicep' = [for rg in resourceGroupNames: {
  name: take('lab-policy-${rg}', 64)
  scope: resourceGroup(rg)
  params: {
    allowedLocations: allowedLocations
    allowedResourceTypes: allowedResourceTypes
    tagsToInherit: tagsToInherit
  }
}]

output resourceGroupsProcessed int = length(resourceGroupNames)
output assignmentsPerGroup int = 2 + length(tagsToInherit)
output allowedLocationList array = allowedLocations
output resourceTypeCount int = length(allowedResourceTypes)
