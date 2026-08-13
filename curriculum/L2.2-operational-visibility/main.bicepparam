using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// The only billed resource in this chapter — and it reads a property off
// L1.4's Front Door, so it hard-fails unless L1.4 is standing. Off by
// default; set CURRICULUM_AVAILABILITY_TEST=true once L1.4 is deployed.
param enableAvailabilityTest = toLower(readEnvironmentVariable('CURRICULUM_AVAILABILITY_TEST', 'false')) == 'true'

// 900 = every 15 minutes per location. Azure allows 300, 600 or 900 and
// nothing else, so this is edited here rather than read from an environment
// variable — readEnvironmentVariable returns a plain int, which the template's
// @allowed union type rejects at compile time. Better a compile error here
// than a rejected deployment. 300 is the portal default and three times the
// price; see the parameter comment in main.bicep.
param testFrequencySeconds = 900
