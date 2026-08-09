using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// Recommendations are much higher volume than alerts and mostly restate the
// L3.1 workbook. Off until you want compliance history over time.
param exportRecommendations = toLower(readEnvironmentVariable('CURRICULUM_EXPORT_RECOMMENDATIONS', 'false')) == 'true'

param minimumAlertSeverity = readEnvironmentVariable('CURRICULUM_MIN_SEVERITY', 'Medium')
