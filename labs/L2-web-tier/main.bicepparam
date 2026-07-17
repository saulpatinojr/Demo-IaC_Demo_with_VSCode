using 'main.bicep'

param prefix = 'iacdemo'
param location = 'eastus2'
param adminUsername = 'azureuser'
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
