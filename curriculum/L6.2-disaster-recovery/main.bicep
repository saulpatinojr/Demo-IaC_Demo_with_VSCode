// ============================================================================
// L6.2 — Disaster Recovery Implementation (builds on L6.1)
// A real regional recovery capability for the VM tier: an Azure Site Recovery
// replication policy and the fabrics it needs, added to the vault L4.1 owns.
//
// What this template does NOT do is enable replication for a specific VM.
// That is deliberate, and it is not a shortcut:
//
//   * Enabling replication is a long-running, stateful operation. It creates
//     replica disks and a cache storage account in the target region, seeds an
//     initial copy that can take hours, and does not converge inside a
//     template deployment. Azure exposes it as an imperative operation for
//     good reason, and the wiki page walks through the CLI command.
//   * It also starts a $25/VM/month meter the moment it succeeds. That
//     deserves to be a decision someone types, not a side effect of a redeploy.
//
// So the template lays the groundwork -- policy and fabrics, both free and
// both idempotent -- and the chapter turns on replication for ONE VM by hand.
// One VM teaches the mechanism; four teaches the same thing at four times the
// price.
//
// Prerequisite: L4.1 (the vault), L6.1 (know what you are protecting first).
// Deploys into a pre-existing resource group (targeted via --resource-group).
// ============================================================================

@description('Same prefix used in Level 1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Primary region — where the Level 1 VMs run.')
param location string = 'eastus2'

@description('Recovery region. Matches the L1.4 secondary so the DR story is consistent across the curriculum.')
param recoveryLocation string = 'westus2'

@description('How long recovery points are kept, in hours. Longer means more replica storage and a wider choice of restore points; 24 is the usual starting answer.')
@minValue(1)
@maxValue(72)
param recoveryPointRetentionHours int = 24

@description('How often an application-consistent snapshot is taken, in hours. Crash-consistent points are continuous; app-consistent ones pause the workload briefly, which is why they are hourly rather than constant.')
@minValue(1)
@maxValue(12)
param appConsistentSnapshotHours int = 4

var vaultName = 'rsv-${prefix}-backup'

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' existing = {
  name: vaultName
}

// Fabrics represent the regions. Azure-to-Azure replication needs one at each
// end, and they are free — they are metadata, not infrastructure.
resource primaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2024-04-01' = {
  parent: vault
  name: 'fabric-${location}'
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: location
    }
  }
}

resource recoveryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2024-04-01' = {
  parent: vault
  name: 'fabric-${recoveryLocation}'
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: recoveryLocation
    }
  }
}

// The policy is the RPO decision written down. Everything else in DR follows
// from these two numbers.
resource replicationPolicy 'Microsoft.RecoveryServices/vaults/replicationPolicies@2024-04-01' = {
  parent: vault
  name: 'asrpol-${prefix}-a2a'
  properties: {
    providerSpecificInput: {
      instanceType: 'A2A'
      recoveryPointHistory: recoveryPointRetentionHours * 60
      appConsistentFrequencyInMinutes: appConsistentSnapshotHours * 60
      crashConsistentFrequencyInMinutes: 5
      multiVmSyncStatus: 'Disable'
    }
  }
}

output replicationPolicyName string = replicationPolicy.name
output fabrics array = [primaryFabric.name, recoveryFabric.name]
output rpoShape object = {
  crashConsistentEvery: '5 minutes'
  appConsistentEvery: '${string(appConsistentSnapshotHours)} hours'
  recoveryPointsKeptFor: '${string(recoveryPointRetentionHours)} hours'
}
output whatIsStillManual string = 'Enabling replication for a VM is an imperative, long-running operation that seeds an initial copy over hours — it does not converge inside a deployment. The wiki page has the az command for one VM.'
output costWhenYouTurnItOn string = 'Azure Site Recovery is $25/month per protected instance (~$0.034/hr), plus replica managed disks in the recovery region (~$1.54/month per 32 GiB Standard HDD), a cache storage account, and egress for the replication traffic. Protect ONE VM.'
output cheaperAlternative string = 'For the stateless tiers, redeploying from this repository costs $0/month in standby and beats paying for warm infrastructure that does nothing. IaC moves the cost-versus-RTO curve; ASR is for the state you cannot redeploy.'
