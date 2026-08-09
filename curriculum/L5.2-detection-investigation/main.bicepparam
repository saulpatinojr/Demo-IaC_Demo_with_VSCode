using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')

// Only true if a Global Administrator or Security Administrator has connected
// Microsoft Entra ID logs in the directory. Otherwise the rule queries an empty
// table and never fires, which looks like coverage and is not.
param includeEntraIdRules = toLower(readEnvironmentVariable('CURRICULUM_ENTRA_RULES', 'false')) == 'true'
