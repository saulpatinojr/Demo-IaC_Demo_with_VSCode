using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')

// Free, and the payoff for L3.3's export work. Needs Sentinel Contributor.
param connectDefenderForCloud = toLower(readEnvironmentVariable('CURRICULUM_CONNECT_DEFENDER', 'true')) == 'true'

// Sentinel charges analysis on everything in the workspace, so a verbose table
// nothing detects on stops being merely wasteful and starts being expensive.
param demoteVerboseTableOnOnboard = toLower(readEnvironmentVariable('CURRICULUM_DEMOTE_VERBOSE', 'true')) == 'true'
