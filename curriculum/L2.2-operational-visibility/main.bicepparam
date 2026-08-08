using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// The only billed resource in this chapter. Set CURRICULUM_AVAILABILITY_TEST
// to false if you skipped L1.4, or to make the chapter cost exactly nothing.
param enableAvailabilityTest = toLower(readEnvironmentVariable('CURRICULUM_AVAILABILITY_TEST', 'true')) == 'true'

// 900 = every 15 minutes per location. Azure allows 300, 600 or 900 and
// nothing else, so this is edited here rather than read from an environment
// variable — readEnvironmentVariable returns a plain int, which the template's
// @allowed union type rejects at compile time. Better a compile error here
// than a rejected deployment. 300 is the portal default and three times the
// price; see the parameter comment in main.bicep.
param testFrequencySeconds = 900
