// ============================================================================
// L4.4 — Enterprise Data Protection Strategy (builds on L4.1–L4.3)
// Turns per-resource backup into a policy with a defensible price: a
// long-retention policy that tiers its own tail into archive, and the
// arithmetic that justifies it.
//
// The policy is added as a CHILD of the vault L4.1 owns -- additive, like
// L2.1's diagnostic settings. What this template deliberately does NOT do is
// change the vault itself. Two of the settings this chapter is about are
// frozen or irreversible, and both belong to L4.1:
//
//   * Redundancy and cross-region restore freeze the moment the first item is
//     protected. If L4.1 deployed LocallyRedundant, cross-region restore is
//     not a setting you can add -- it is a vault you have to rebuild.
//   * Immutability, once LOCKED, cannot be undone by anyone, including
//     Microsoft support. That is the point of it, and it is why this template
//     will not set it for you.
//
// Cost: the policy itself is free. Retention x redundancy x protected
// instances is the whole formula, and archive tiering is the one lever that
// cuts storage without shortening the compliance answer.
//
// Prerequisite: L4.1 (the vault), L4.3 (you should be able to see job history
// before you extend retention).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Daily recovery points kept in the standard tier before archive becomes eligible.')
@minValue(7)
@maxValue(9999)
param dailyRetentionDays int = 30

@description('Monthly recovery points to keep, in months. This is the compliance answer — 12 months of month-ends is the usual starting point.')
@minValue(0)
@maxValue(120)
param monthlyRetentionMonths int = 12

@description('Yearly recovery points to keep, in years. 7 is the common regulatory figure and the single most expensive line in most backup estates — which is why this chapter prices it before setting it.')
@minValue(0)
@maxValue(10)
param yearlyRetentionYears int = 7

@description('Move eligible recovery points to the archive tier after this many months. Archive is $0.0027/GB/month LRS against $0.0224 standard — better than a 90% cut on the long tail, and it preserves the compliance answer instead of shortening it.')
@minValue(3)
@maxValue(120)
param archiveAfterMonths int = 6

@description('Assign the built-in policy that audits whether VMs are backed up. OFF by default: plain Contributor cannot create a policy assignment — Microsoft.Authorization/*/Write is in the role\'s notActions. Same wall as L2.4.')
param assignBackupAuditPolicy bool = false

var vaultName = 'rsv-${prefix}-backup'
var policyName = 'bkpol-${prefix}-longterm'

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
}

// A second policy alongside L4.1's daily one, not a replacement for it. Move
// an item onto this policy to see the retention and storage change; leave the
// rest where they are and compare.
resource longTermPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: vault
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
        scheduleRunTimes: ['2024-01-01T02:00:00Z']
      }
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: ['2024-01-01T02:00:00Z']
        retentionDuration: {
          count: dailyRetentionDays
          durationType: 'Days'
        }
      }
      monthlySchedule: monthlyRetentionMonths > 0
        ? {
            retentionScheduleFormatType: 'Weekly'
            retentionScheduleWeekly: {
              daysOfTheWeek: ['Sunday']
              weeksOfTheMonth: ['First']
            }
            retentionTimes: ['2024-01-01T02:00:00Z']
            retentionDuration: {
              count: monthlyRetentionMonths
              durationType: 'Months'
            }
          }
        : null
      yearlySchedule: yearlyRetentionYears > 0
        ? {
            retentionScheduleFormatType: 'Weekly'
            monthsOfYear: ['January']
            retentionScheduleWeekly: {
              daysOfTheWeek: ['Sunday']
              weeksOfTheMonth: ['First']
            }
            retentionTimes: ['2024-01-01T02:00:00Z']
            retentionDuration: {
              count: yearlyRetentionYears
              durationType: 'Years'
            }
          }
        : null
    }
    // The lever. Everything older than archiveAfterMonths moves to a tier
    // costing about an eighth as much, and the retention promise is unchanged.
    tieringPolicy: {
      ArchivedRP: {
        tieringMode: 'TierAfter'
        duration: archiveAfterMonths
        durationType: 'Months'
      }
    }
  }
}

// Built-in "Azure Backup should be enabled for Virtual Machines", AuditIfNotExists.
resource backupAudit 'Microsoft.Authorization/policyAssignments@2024-04-01' = if (assignBackupAuditPolicy) {
  name: 'audit-backup-${prefix}'
  properties: {
    displayName: 'Audit VMs without backup (${prefix})'
    description: 'Reports virtual machines in this group with no Azure Backup protection. Audit only — enrolling them is a pull request against L4.1.'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/013e242c-8828-4970-87b3-ab247555486d'
    enforcementMode: 'Default'
  }
}

output longTermPolicyName string = policyName
output retentionShape object = {
  daily: '${string(dailyRetentionDays)} days'
  monthly: monthlyRetentionMonths > 0 ? '${string(monthlyRetentionMonths)} months' : 'none'
  yearly: yearlyRetentionYears > 0 ? '${string(yearlyRetentionYears)} years' : 'none'
  archiveAfter: '${string(archiveAfterMonths)} months'
}
output theWholeFormula string = 'Retention x redundancy x protected instances. Change one variable at a time and watch the total move — that exercise is the chapter.'
output archiveSaving string = 'Archive is $0.0027/GB/month LRS against $0.0224 standard. Tiering the long tail cuts that storage by about 88% and keeps the same retention promise, which is why it beats shortening retention.'
output whatL41Froze string = 'Redundancy and cross-region restore were fixed when L4.1 protected its first item. If you need them changed, the vault has to be rebuilt — which is the reason L4.1 asked before it deployed.'
output immutabilityWarning string = 'Immutability belongs on the vault, and LOCKED is irreversible by anyone including Microsoft support. Set it deliberately in L4.1, never as a default here.'
