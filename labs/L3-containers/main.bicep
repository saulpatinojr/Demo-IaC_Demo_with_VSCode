// ============================================================================
// L3 — Containers + Data + Private Networking (builds on L1/L2)
// Swaps the VM web tier for Azure Container Apps, adds an Azure SQL backend,
// Key Vault, managed identity, monitoring and alerting. This is where PRIVATE
// networking is introduced: SQL and Key Vault have public access disabled and
// are reachable only through private endpoints in a new spoke peered to L1's
// hub. The container app itself stays publicly reachable so you can test it.
// Prerequisite: L1 deployed (same prefix). L2 is not required but can coexist.
// ============================================================================
targetScope = 'subscription'

@description('Same prefix used in L1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in L1.')
param location string = 'eastus2'

@description('Resource group created by L1.')
param l1ResourceGroupName string = 'rg-${prefix}-l1'

@description('SQL admin login name.')
param sqlAdminLogin string = 'sqladminuser'

@description('SQL admin password.')
@secure()
param sqlAdminPassword string

@description('Email address for the alert action group.')
param alertEmail string = 'you@example.com'

var rgName = 'rg-${prefix}-l3'
var hubVnetName = 'vnet-${prefix}-hub'
// uniqueString keeps globally-unique names (SQL, KV) stable per subscription.
var suffix = take(uniqueString(subscription().id, prefix), 6)

resource l1Rg 'Microsoft.Resources/resourceGroups@2024-11-01' existing = {
  name: l1ResourceGroupName
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  scope: l1Rg
  name: hubVnetName
}

resource rg 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: rgName
  location: location
  tags: { lab: 'L3', demo: prefix }
}

// --- New spoke: ACA infrastructure + private endpoints, peered to L1 hub ---
module spoke2 'br/public:avm/res/network/virtual-network:0.9.0' = {
  scope: rg
  name: 'l3-spoke2-vnet'
  params: {
    name: 'vnet-${prefix}-spoke2'
    location: location
    addressPrefixes: ['10.2.0.0/16']
    subnets: [
      {
        name: 'snet-aca'
        addressPrefix: '10.2.0.0/23'
        delegation: 'Microsoft.App/environments'
      }
      {
        name: 'snet-private-endpoints'
        addressPrefix: '10.2.2.0/24'
      }
    ]
    peerings: [
      {
        remoteVirtualNetworkResourceId: hubVnet.id
        allowForwardedTraffic: true
        remotePeeringEnabled: true
        remotePeeringAllowForwardedTraffic: true
      }
    ]
  }
}

// --- Private DNS zones for SQL + Key Vault private endpoints ---------------
module sqlDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  scope: rg
  name: 'l3-sql-dns'
  params: {
    name: 'privatelink${environment().suffixes.sqlServerHostname}'
    virtualNetworkLinks: [
      { virtualNetworkResourceId: spoke2.outputs.resourceId }
    ]
  }
}

module kvDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  scope: rg
  name: 'l3-kv-dns'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    virtualNetworkLinks: [
      { virtualNetworkResourceId: spoke2.outputs.resourceId }
    ]
  }
}

// --- Monitoring foundation ---------------------------------------------------
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.15.1' = {
  scope: rg
  name: 'l3-log-analytics'
  params: {
    name: 'log-${prefix}-l3'
    location: location
    dataRetention: 30
  }
}

module appInsights 'br/public:avm/res/insights/component:0.7.2' = {
  scope: rg
  name: 'l3-app-insights'
  params: {
    name: 'appi-${prefix}-l3'
    location: location
    workspaceResourceId: logAnalytics.outputs.resourceId
  }
}

// --- Managed identity for the app -------------------------------------------
module appIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  scope: rg
  name: 'l3-app-identity'
  params: {
    name: 'id-${prefix}-app'
    location: location
  }
}

// --- Key Vault: public access OFF, private endpoint only --------------------
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: rg
  name: 'l3-key-vault'
  params: {
    name: 'kv-${prefix}-${suffix}'
    location: location
    sku: 'standard'
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { bypass: 'AzureServices', defaultAction: 'Deny' }
    privateEndpoints: [
      {
        subnetResourceId: spoke2.outputs.subnetResourceIds[1]
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            { privateDnsZoneResourceId: kvDnsZone.outputs.resourceId }
          ]
        }
      }
    ]
    secrets: [
      {
        name: 'sql-connection-string'
        value: 'Server=tcp:sql-${prefix}-${suffix}${environment().suffixes.sqlServerHostname},1433;Database=sqldb-${prefix}-app;Authentication=Active Directory Managed Identity;'
      }
    ]
    roleAssignments: [
      {
        principalId: appIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
    ]
  }
}

// --- Azure SQL: public access OFF, private endpoint only --------------------
module sqlServer 'br/public:avm/res/sql/server:0.21.4' = {
  scope: rg
  name: 'l3-sql-server'
  params: {
    name: 'sql-${prefix}-${suffix}'
    location: location
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled'
    databases: [
      {
        name: 'sqldb-${prefix}-app'
        availabilityZone: -1
        zoneRedundant: false
        sku: { name: 'Basic', tier: 'Basic' }
        maxSizeBytes: 2147483648
      }
    ]
    privateEndpoints: [
      {
        service: 'sqlServer'
        subnetResourceId: spoke2.outputs.subnetResourceIds[1]
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            { privateDnsZoneResourceId: sqlDnsZone.outputs.resourceId }
          ]
        }
      }
    ]
  }
}

// --- Container Apps environment (VNet-integrated, public ingress) ----------
module acaEnv 'br/public:avm/res/app/managed-environment:0.13.3' = {
  scope: rg
  name: 'l3-aca-env'
  params: {
    name: 'cae-${prefix}-l3'
    location: location
    infrastructureSubnetResourceId: spoke2.outputs.subnetResourceIds[0]
    internal: false
    zoneRedundant: false
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    }
  }
}

// --- The app (public quickstart image) --------------------------------------
module webApp 'br/public:avm/res/app/container-app:0.23.0' = {
  scope: rg
  name: 'l3-container-app'
  params: {
    name: 'ca-${prefix}-web'
    location: location
    environmentResourceId: acaEnv.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [appIdentity.outputs.resourceId]
    }
    ingressExternal: true
    ingressTargetPort: 80
    scaleSettings: { minReplicas: 1, maxReplicas: 3 }
    containers: [
      {
        name: 'web'
        image: 'mcr.microsoft.com/k8se/quickstart:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'KEY_VAULT_URI', value: keyVault.outputs.uri }
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: appInsights.outputs.connectionString
          }
          { name: 'AZURE_CLIENT_ID', value: appIdentity.outputs.clientId }
        ]
      }
    ]
  }
}

// --- Alerting: email when the app's CPU runs hot ----------------------------
module actionGroup 'br/public:avm/res/insights/action-group:0.8.0' = {
  scope: rg
  name: 'l3-action-group'
  params: {
    name: 'ag-${prefix}-ops'
    groupShortName: 'iacdemoops'
    emailReceivers: [
      {
        name: 'opsEmail'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

module cpuAlert 'br/public:avm/res/insights/metric-alert:0.4.1' = {
  scope: rg
  name: 'l3-cpu-alert'
  params: {
    name: 'alert-${prefix}-app-replicas'
    scopes: [webApp.outputs.resourceId]
    targetResourceType: 'Microsoft.App/containerApps'
    targetResourceRegion: location
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allof: [
        {
          name: 'HighReplicaCount'
          metricName: 'Replicas'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThanOrEqual'
          threshold: 2
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [actionGroup.outputs.resourceId]
  }
}

output resourceGroupName string = rgName
output appUrl string = 'https://${webApp.outputs.fqdn}'
output sqlServerName string = sqlServer.outputs.name
output keyVaultName string = keyVault.outputs.name
output logAnalyticsName string = logAnalytics.outputs.name
