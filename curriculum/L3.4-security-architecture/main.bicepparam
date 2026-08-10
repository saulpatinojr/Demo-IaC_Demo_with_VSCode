using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')

// Premium_AzureFrontDoor unlocks managed rule sets and costs about +$0.40/hr.
// Standard is the default for a reason; change it in an instructor-led window
// and change it back.
param wafSku = readEnvironmentVariable('CURRICULUM_WAF_SKU', 'Standard_AzureFrontDoor')

// Detection logs, Prevention blocks. Start in Detection.
param wafMode = readEnvironmentVariable('CURRICULUM_WAF_MODE', 'Detection')
