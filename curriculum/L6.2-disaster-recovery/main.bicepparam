using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// Matches the L1.4 secondary region so the DR story stays consistent.
param recoveryLocation = readEnvironmentVariable('CURRICULUM_DR_REGION', 'westus2')
