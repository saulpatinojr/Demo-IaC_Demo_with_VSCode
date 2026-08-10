using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')

// The expensive line. Set it to 0 and compare the storage forecast before you
// agree to 7 years on anything real.
param yearlyRetentionYears = int(readEnvironmentVariable('CURRICULUM_YEARLY_RETENTION', '7'))

// Off unless you hold Resource Policy Contributor or Owner — same wall as L2.4.
param assignBackupAuditPolicy = toLower(readEnvironmentVariable('CURRICULUM_ASSIGN_POLICY', 'false')) == 'true'
