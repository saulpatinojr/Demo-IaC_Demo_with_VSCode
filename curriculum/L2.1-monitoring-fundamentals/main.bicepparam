using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// Set CURRICULUM_INCLUDE_WEB_TIER=false if you tore L1.2 down to save money.
param includeWebTier = toLower(readEnvironmentVariable('CURRICULUM_INCLUDE_WEB_TIER', 'true')) == 'true'

// Main path (L1.1 -> L2.1) leaves this false and gets a self-created
// workspace. Set CURRICULUM_INCLUDE_APP_TIER=true once L1.3 is deployed so
// its Key Vault, SQL database and container app get diagnostic settings and
// its workspace is reused instead.
param includeAppTier = toLower(readEnvironmentVariable('CURRICULUM_INCLUDE_APP_TIER', 'false')) == 'true'

// Both of these are cost dials — see the comments on the parameters in
// main.bicep before flipping either one on.
param sendPlatformMetricsToLogs = toLower(readEnvironmentVariable('CURRICULUM_METRICS_TO_LOGS', 'false')) == 'true'
param collectFirewallLogs = toLower(readEnvironmentVariable('CURRICULUM_FIREWALL_LOGS', 'true')) == 'true'
