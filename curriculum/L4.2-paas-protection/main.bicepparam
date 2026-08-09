using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param includeSecondaryRegion = toLower(readEnvironmentVariable('CURRICULUM_SECONDARY_REGION', 'true')) == 'true'

// The Basic tier caps PITR at 7 days. Asking for 35 here is rejected by Azure,
// not by this template — try it once and read the error.
param pitrRetentionDays = int(readEnvironmentVariable('CURRICULUM_PITR_DAYS', '7'))
