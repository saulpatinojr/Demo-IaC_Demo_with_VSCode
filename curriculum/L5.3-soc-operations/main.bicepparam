using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// Argue about this one before enabling it. An auto-closed incident is one
// nobody looked at.
param autoCloseLowSeverity = toLower(readEnvironmentVariable('CURRICULUM_AUTO_CLOSE', 'false')) == 'true'
