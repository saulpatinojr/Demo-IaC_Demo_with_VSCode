// ============================================================================
// L4.2 — PaaS Protection (builds on L4.1)
// Protects the data that is not on a disk. Azure SQL is the interesting case:
// point-in-time restore is already on and already paid for, and most teams
// discover that only after an incident, so this chapter is as much about
// verifying what exists as about configuring what does not.
//
// Both policies here are CHILDREN of the SQL databases, added the same way
// L2.1 added diagnostic settings to resources it did not create. Adding a
// child is safe; editing another template's resource is not.
//
// Cost: PITR within the included retention is free at 1x database size. LTR
// storage is $0.025/GB/month LRS or $0.05/GB/month RA-GRS -- pennies for a lab
// database, and the reason this chapter is nearly free.
//
// Prerequisite: L4.1 (the vault concepts), L1.3 and L1.4 (the SQL servers).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('L1.4 deployed a second-region SQL server. Set false if you stopped at L1.3.')
param includeSecondaryRegion bool = true

@description('Point-in-time restore window, in days. The Basic service tier the lab uses CAPS THIS AT 7 — asking for more is rejected, which is itself worth seeing. Higher tiers allow up to 35.')
@minValue(1)
@maxValue(35)
param pitrRetentionDays int = 7

@description('Weekly long-term recovery points to keep, ISO 8601. P4W keeps four; PT0S disables weekly LTR entirely.')
param weeklyLtrRetention string = 'P4W'

@description('Monthly long-term recovery points to keep. P12M is the usual answer to "we need a year of month-ends".')
param monthlyLtrRetention string = 'P12M'

@description('Yearly long-term recovery points to keep. PT0S by default — a 7-year yearly policy is the single most expensive line in most real backup estates, and this chapter prices it rather than setting it.')
param yearlyLtrRetention string = 'PT0S'

var suffix = take(uniqueString(subscription().id, prefix), 6)
var databaseName = 'sqldb-${prefix}-app'

resource primaryDatabase 'Microsoft.Sql/servers/databases@2023-08-01' existing = {
  name: 'sql-${prefix}-${suffix}/${databaseName}'
}

resource secondaryDatabase 'Microsoft.Sql/servers/databases@2023-08-01' existing = if (includeSecondaryRegion) {
  name: 'sql-${prefix}-${suffix}-dr/${databaseName}'
}

// --- Point-in-time restore -------------------------------------------------
// This is the one people forget is already running. Azure SQL has been taking
// backups since L1.3 deployed, at no extra charge, and the only decision here
// is how far back the window reaches.
resource primaryPitr 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2023-08-01' = {
  parent: primaryDatabase
  name: 'default'
  properties: {
    retentionDays: pitrRetentionDays
  }
}

// --- Long-term retention ---------------------------------------------------
// PITR answers "undo the last few days". LTR answers "produce the month-end
// from eighteen months ago", which is a compliance question, not an
// operational one -- and the storage bill scales with how confidently you
// answer it.
resource primaryLtr 'Microsoft.Sql/servers/databases/backupLongTermRetentionPolicies@2023-08-01' = {
  parent: primaryDatabase
  name: 'default'
  properties: {
    weeklyRetention: weeklyLtrRetention
    monthlyRetention: monthlyLtrRetention
    yearlyRetention: yearlyLtrRetention
    weekOfYear: 1
  }
}

// The geo-secondary gets its own PITR window. Worth stating plainly: this is
// NOT what protects you from a deletion. The failover group replicates a
// DROP TABLE faithfully and immediately.
resource secondaryPitr 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2023-08-01' = if (includeSecondaryRegion) {
  parent: secondaryDatabase
  name: 'default'
  properties: {
    retentionDays: pitrRetentionDays
  }
}

output pitrWindowDays int = pitrRetentionDays
output ltrPolicy object = {
  weekly: weeklyLtrRetention
  monthly: monthlyLtrRetention
  yearly: yearlyLtrRetention
}
output whatIsNotProtected array = [
  'Container Apps configuration — redeploy from curriculum/L1.3-multi-service-application instead'
  'Private DNS zone records — redeploy from curriculum/L1.3-multi-service-application instead'
  'Key Vault — soft delete and purge protection are already on from L1.3; verify, do not re-create'
  'Blob storage — the lab deploys no storage account, so there is nothing to protect with a Backup vault'
]
output replicationIsNotBackup string = 'The L1.4 failover group replicates a deletion faithfully. PITR is what undoes it. If a chapter here teaches one sentence, it is that one.'
output ltrCostBasis string = 'LTR storage is $0.025/GB/month LRS, $0.05/GB/month RA-GRS. Price a 7-year yearly policy on a real database before you agree to one.'
