// ============================================================================
// L4.1 — Backup Fundamentals (builds on Levels 1–3)
// Protects the Level 1 virtual machines: a Recovery Services vault, a backup
// policy derived from a stated retention requirement, and the protected items
// that put the two together.
//
// ORDERING MATTERS HERE, and it is the chapter's hardest lesson: vault
// redundancy (LRS / ZRS / GRS) can only be changed while the vault has NEVER
// protected anything. Once the first item is registered the setting is frozen
// for the life of the vault. So the storage config below is deployed before
// the protected items, and enableCrossRegionRestore has to be decided now --
// L4.4 will ask for it and will not be able to turn it on retrospectively.
//
// Cost: $10/month per protected VM instance, plus backup storage at
// $0.0448/GB/month GRS ($0.0224 LRS). Four VMs and ~40 GB of compressed OS
// disk is about $41.79/month, roughly $0.057/hr.
//
// This is also the one cost in the curriculum that SURVIVES TEARDOWN. Deleting
// a VM does not delete its recovery points, and a vault with soft delete on
// keeps billing for retained data after the source is gone. See the wiki page.
//
// Prerequisite: L1.1 and L1.2 (the VMs).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in Level 1.')
param location string = 'eastus2'

@description('Set false if you tore down L1.2 — its three web VMs are then left unprotected.')
param includeWebTier bool = true

@description('Vault redundancy. GeoRedundant is the default and the only option that can later support cross-region restore; LocallyRedundant is half the storage price and cannot. IMMUTABLE ONCE ANYTHING IS PROTECTED — choose it now or rebuild the vault later.')
@allowed(['LocallyRedundant', 'ZoneRedundant', 'GeoRedundant'])
param vaultRedundancy string = 'GeoRedundant'

@description('Enable cross-region restore. Requires GeoRedundant and upgrades the storage meter from $0.0448 to $0.0569/GB/month. L4.4 needs this and cannot turn it on afterwards.')
param enableCrossRegionRestore bool = false

@description('Hour of the day (UTC) the daily backup runs. 02:00 by default, which is inside the maintenance window L2.3 suppresses alerts for — deliberately, so a backup-window blip does not page anyone.')
@allowed(['02:00', '03:00', '22:00'])
param backupTimeUtc string = '02:00'

@description('Daily recovery points to keep.')
@minValue(7)
@maxValue(9999)
param dailyRetentionDays int = 30

@description('Weekly recovery points to keep, in weeks. Set 0 to keep dailies only and see how much less the storage line is.')
@minValue(0)
@maxValue(520)
param weeklyRetentionWeeks int = 12

var vmNames = union(
  ['vm-${prefix}-test'],
  includeWebTier ? ['vm-${prefix}-web0', 'vm-${prefix}-web1', 'vm-${prefix}-web2'] : []
)

var policyName = 'bkpol-${prefix}-daily'
var vaultName = 'rsv-${prefix}-backup'

// Cross-region restore is only meaningful on geo-redundant storage. Rather
// than let a contradictory pair deploy and fail late, resolve it here.
var crossRegionRestore = enableCrossRegionRestore && vaultRedundancy == 'GeoRedundant'

module vault 'br/public:avm/res/recovery-services/vault:0.10.0' = {
  name: 'l41-vault'
  params: {
    name: vaultName
    location: location
    // Soft delete keeps deleted recovery points for 14 days. It is what
    // defeats "the attacker deleted the backups too", and it is also why
    // deleting this lab does not immediately stop the storage meter.
    softDeleteSettings: {
      softDeleteState: 'Enabled'
      softDeleteRetentionPeriodInDays: 14
      // Enhanced security is what makes soft delete resistant to a malicious
      // admin rather than merely to an accident: disabling it then requires
      // multi-factor authorisation.
      enhancedSecurityState: 'Enabled'
    }
    backupPolicies: [
      {
        name: policyName
        properties: {
          backupManagementType: 'AzureIaasVM'
          policyType: 'V2'
          instantRpRetentionRangeInDays: 2
          timeZone: 'UTC'
          schedulePolicy: {
            schedulePolicyType: 'SimpleSchedulePolicyV2'
            scheduleRunFrequency: 'Daily'
            dailySchedule: {
              scheduleRunTimes: ['2024-01-01T${backupTimeUtc}:00Z']
            }
          }
          retentionPolicy: {
            retentionPolicyType: 'LongTermRetentionPolicy'
            dailySchedule: {
              retentionTimes: ['2024-01-01T${backupTimeUtc}:00Z']
              retentionDuration: {
                count: dailyRetentionDays
                durationType: 'Days'
              }
            }
            weeklySchedule: weeklyRetentionWeeks > 0
              ? {
                  daysOfTheWeek: ['Sunday']
                  retentionTimes: ['2024-01-01T${backupTimeUtc}:00Z']
                  retentionDuration: {
                    count: weeklyRetentionWeeks
                    durationType: 'Weeks'
                  }
                }
              : null
          }
        }
      }
    ]
  }
}

// Storage config as a raw child rather than through the module: the AVM
// module's backupConfig type does not expose crossRegionRestoreFlag, and that
// flag is the whole point of the decision this chapter forces you to make now.
resource storageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2024-04-01' = {
  parent: vaultRef
  name: 'vaultstorageconfig'
  properties: {
    storageModelType: vaultRedundancy
    crossRegionRestoreFlag: crossRegionRestore
  }
}

resource vms 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [
  for name in vmNames: {
    name: name
  }
]

resource vaultRef 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
  dependsOn: [
    vault
  ]
}

// The protected item. Those semicolon-separated names are not a typo -- Azure
// Backup addresses IaaS VMs through a container/item pair whose names encode
// the resource group and VM name, and getting them wrong is the most common
// reason this resource fails with an unhelpful message.
resource protectedItems 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = [
  for (name, i) in vmNames: {
    name: '${vaultName}/Azure/iaasvmcontainer;iaasvmcontainerv2;${resourceGroup().name};${name}/vm;iaasvmcontainerv2;${resourceGroup().name};${name}'
    properties: {
      protectedItemType: 'Microsoft.Compute/virtualMachines'
      sourceResourceId: vms[i].id
      policyId: '${vaultRef.id}/backupPolicies/${policyName}'
    }
    // The ordering lesson, enforced: redundancy freezes the moment anything is
    // protected, so the storage config has to land first.
    dependsOn: [
      storageConfig
    ]
  }
]

output vaultResourceId string = vaultRef.id
output protectedVmCount int = length(vmNames)
output redundancy string = vaultRedundancy
output crossRegionRestoreEnabled bool = crossRegionRestore
output redundancyIsFrozen string = 'Vault redundancy cannot be changed once anything is protected. If L4.4 needs cross-region restore and this says false, the vault has to be rebuilt.'
output monthlyCost string = '${string(length(vmNames))} protected instance(s) at $10/month = $${string(length(vmNames) * 10)}/month, plus backup storage at ${vaultRedundancy == 'LocallyRedundant' ? '$0.0224' : (vaultRedundancy == 'ZoneRedundant' ? '$0.0280' : (crossRegionRestore ? '$0.0569' : '$0.0448'))}/GB/month.'
output survivesTeardown string = 'Deleting the VMs does NOT delete their recovery points, and soft delete holds them for 14 more days. Empty the vault before you delete the resource group, or the storage meter keeps running.'
