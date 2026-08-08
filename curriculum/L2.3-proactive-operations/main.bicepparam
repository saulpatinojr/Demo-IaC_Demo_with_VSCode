using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', 'you@example.com')

// A second inbox, so a signal does not die because one person is away. Empty
// is allowed and gives you a single receiver.
param secondaryAlertEmail = readEnvironmentVariable('ALERT_EMAIL_SECONDARY', '')

param includeWebTier = toLower(readEnvironmentVariable('CURRICULUM_INCLUDE_WEB_TIER', 'true')) == 'true'
param enableMaintenanceSuppression = toLower(readEnvironmentVariable('CURRICULUM_SUPPRESS_MAINTENANCE', 'true')) == 'true'
