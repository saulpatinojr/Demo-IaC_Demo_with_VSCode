using 'main.bicep'

param prefix = 'iacdemo'
param location = 'eastus2'
param adminUsername = 'azureuser'
// Supplied at deploy time (workflow secret or CLI prompt) — never commit passwords.
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
