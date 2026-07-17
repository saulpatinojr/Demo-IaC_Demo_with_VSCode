using 'main.bicep'

param prefix = 'iacdemo'
param secondaryLocation = 'westus2'
param sqlAdminLogin = 'sqladminuser'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD', '')
