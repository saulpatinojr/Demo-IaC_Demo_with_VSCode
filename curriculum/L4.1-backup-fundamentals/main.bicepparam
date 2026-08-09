using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param includeWebTier = toLower(readEnvironmentVariable('CURRICULUM_INCLUDE_WEB_TIER', 'true')) == 'true'

// Decide both of these NOW. Redundancy freezes the moment the first item is
// protected, and cross-region restore cannot be added to a vault afterwards --
// L4.4 asks for it and will not be able to turn it on retrospectively.
param vaultRedundancy = readEnvironmentVariable('CURRICULUM_VAULT_REDUNDANCY', 'GeoRedundant')
param enableCrossRegionRestore = toLower(readEnvironmentVariable('CURRICULUM_CROSS_REGION_RESTORE', 'false')) == 'true'
