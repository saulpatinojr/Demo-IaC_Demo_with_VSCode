// Creates a failover group on an EXISTING primary SQL server (deployed by L3).
// Local module: the AVM sql/server module only supports failover groups on
// servers it creates itself, not on pre-existing ones.
param primaryServerName string
param failoverGroupName string
param partnerServerResourceId string
param databaseNames array

resource primaryServer 'Microsoft.Sql/servers@2023-08-01' existing = {
  name: primaryServerName
}

resource failoverGroup 'Microsoft.Sql/servers/failoverGroups@2023-08-01' = {
  parent: primaryServer
  name: failoverGroupName
  properties: {
    partnerServers: [
      { id: partnerServerResourceId }
    ]
    readWriteEndpoint: {
      failoverPolicy: 'Automatic'
      failoverWithDataLossGracePeriodMinutes: 60
    }
    databases: [for db in databaseNames: resourceId('Microsoft.Sql/servers/databases', primaryServerName, db)]
  }
}

output listenerEndpoint string = '${failoverGroupName}${environment().suffixes.sqlServerHostname}'
