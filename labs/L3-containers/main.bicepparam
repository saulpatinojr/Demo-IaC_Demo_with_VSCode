using 'main.bicep'

param prefix = 'iacdemo'
param location = 'eastus2'
param sqlAdminLogin = 'sqladminuser'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD', '')
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', 'you@example.com')
