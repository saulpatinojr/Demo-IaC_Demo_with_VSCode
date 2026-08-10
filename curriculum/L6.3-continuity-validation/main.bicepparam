using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

// An SLO you meet every week teaches nothing; one you can never meet gets
// ignored. 99% over 24 hours is deliberately reachable and occasionally missed.
param availabilityTargetPercent = int(readEnvironmentVariable('CURRICULUM_SLO_PERCENT', '99'))
