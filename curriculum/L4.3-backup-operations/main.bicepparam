using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// Read the wiki page first. A Resource Guard in the same subscription, under
// the same administrators, protects against accident and not against the
// threat MUA exists for.
param deployResourceGuard = toLower(readEnvironmentVariable('CURRICULUM_RESOURCE_GUARD', 'false')) == 'true'
