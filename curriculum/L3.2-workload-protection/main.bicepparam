using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', 'you@example.com')

// Set false if you stopped at L1.3 — there is no second-region SQL server to
// protect, and pointing at one that does not exist fails the deployment.
param includeSecondaryRegion = toLower(readEnvironmentVariable('CURRICULUM_SECONDARY_REGION', 'true')) == 'true'

param includeWebTier = toLower(readEnvironmentVariable('CURRICULUM_INCLUDE_WEB_TIER', 'true')) == 'true'

// Needs Defender for Servers Plan 2 on the subscription, which is an
// instructor decision and three times the price of Plan 1. Off until it is on.
param enableJitAccess = toLower(readEnvironmentVariable('CURRICULUM_ENABLE_JIT', 'false')) == 'true'
