// ============================================================================
// L4 — Global Scale (builds on L3)
// The "upgrade" of L3: a second-region copy of the app tier, an Azure SQL
// failover group between the L3 (primary) and new secondary SQL server, and
// Azure Front Door as the single global entry point with health-probed
// failover between the two regions.
// Prerequisite: L3 deployed (same prefix, same resource group).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in L1–L3.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Secondary region for the failover stack.')
param secondaryLocation string = 'westus2'

@description('SQL admin login (must match L3).')
param sqlAdminLogin string = 'sqladminuser'

@description('SQL admin password (must match L3).')
@secure()
param sqlAdminPassword string

var suffix = take(uniqueString(subscription().id, prefix), 6)
var primarySqlServerName = 'sql-${prefix}-${suffix}'
var appDatabaseName = 'sqldb-${prefix}-app'

// L3's container app — Front Door's primary origin.
resource primaryApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: 'ca-${prefix}-web'
}

// --- Secondary region: Container Apps stack (slim — no VNet, public) -------
// publicNetworkAccess must be explicit: the AVM module defaults it to
// 'Disabled', which would leave this origin unreachable and fail Front Door's
// health probes below.
module acaEnv2 'br/public:avm/res/app/managed-environment:0.13.3' = {
  name: 'l4-aca-env-secondary'
  params: {
    name: 'cae-${prefix}-l4'
    location: secondaryLocation
    zoneRedundant: false
    publicNetworkAccess: 'Enabled'
  }
}

module webApp2 'br/public:avm/res/app/container-app:0.23.0' = {
  name: 'l4-container-app-secondary'
  params: {
    name: 'ca-${prefix}-web2'
    location: secondaryLocation
    environmentResourceId: acaEnv2.outputs.resourceId
    ingressExternal: true
    ingressTargetPort: 80
    scaleSettings: { minReplicas: 1, maxReplicas: 3 }
    containers: [
      {
        name: 'web'
        image: 'mcr.microsoft.com/k8se/quickstart:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'REGION', value: secondaryLocation }
        ]
      }
    ]
  }
}

// --- Secondary SQL server + failover group ----------------------------------
module sqlSecondary 'br/public:avm/res/sql/server:0.21.4' = {
  name: 'l4-sql-secondary'
  params: {
    name: 'sql-${prefix}-${suffix}-dr'
    location: secondaryLocation
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled'
  }
}

// Failover group lives on the PRIMARY server (in same resource group as L3).
module failoverGroup '../modules/sql-failover-group.bicep' = {
  name: 'l4-sql-failover-group'
  params: {
    primaryServerName: primarySqlServerName
    failoverGroupName: 'fog-${prefix}-${suffix}'
    partnerServerResourceId: sqlSecondary.outputs.resourceId
    databaseNames: [appDatabaseName]
  }
}

// --- Azure Front Door (Standard): global entry, health-probed failover -----
module frontDoor 'br/public:avm/res/cdn/profile:0.19.3' = {
  name: 'l4-front-door'
  params: {
    name: 'afd-${prefix}-${suffix}'
    location: 'global'
    sku: 'Standard_AzureFrontDoor'
    originGroups: [
      {
        name: 'og-web'
        loadBalancingSettings: {
          sampleSize: 4
          successfulSamplesRequired: 3
          additionalLatencyInMilliseconds: 50
        }
        healthProbeSettings: {
          probePath: '/'
          probeProtocol: 'Https'
          probeRequestType: 'GET'
          probeIntervalInSeconds: 30
        }
        origins: [
          {
            name: 'primary-app'
            hostName: primaryApp.properties.configuration.ingress.fqdn
            originHostHeader: primaryApp.properties.configuration.ingress.fqdn
            priority: 1 // preferred
          }
          {
            name: 'secondary-app'
            hostName: webApp2.outputs.fqdn
            originHostHeader: webApp2.outputs.fqdn
            priority: 2 // failover
          }
        ]
      }
    ]
    afdEndpoints: [
      {
        name: 'fde-${prefix}'
        routes: [
          {
            name: 'route-web'
            originGroupName: 'og-web'
            supportedProtocols: ['Http', 'Https']
            httpsRedirect: 'Enabled'
            forwardingProtocol: 'HttpsOnly'
            linkToDefaultDomain: 'Enabled'
            patternsToMatch: ['/*']
          }
        ]
      }
    ]
  }
}

output resourceGroupName string = resourceGroup().name
output frontDoorEndpoint string = 'https://${frontDoor.outputs.frontDoorEndpointHostNames[0]}'
output secondaryAppUrl string = 'https://${webApp2.outputs.fqdn}'
output failoverGroupListener string = failoverGroup.outputs.listenerEndpoint
