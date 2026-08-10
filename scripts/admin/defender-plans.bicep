// ============================================================================
// Defender for Cloud plans -- subscription scope
//
// Defender plans are Microsoft.Security/pricings resources, which live at
// SUBSCRIPTION scope. Lab participants hold Contributor on one resource
// group, which cannot enable them at any price -- so this template is an
// instructor deployment, run once per lab subscription:
//
//     az deployment sub create --location eastus2 \
//       --template-file scripts/admin/defender-plans.bicep
//
// Enable-DefenderPlans.ps1 wraps that command with the cost preview the
// template itself cannot do (per-node pricing bills whatever already lives
// in the subscription, and only a reader can count that). The resource
// writes all happen here, where what-if and the diff can see them.
//
// Enabling a plan bills the WHOLE subscription, not just the lab resource
// groups, every hour, until set back to Free (deploy with enabled=false).
// ============================================================================
targetScope = 'subscription'

@description('Defender for Servers sub-plan. P2 adds vulnerability assessment, file integrity monitoring and JIT VM access -- L3.2\'s JIT exercise needs it -- at three times the price. None skips Defender for Servers entirely.')
@allowed(['None', 'P1', 'P2'])
param serversPlan string = 'P1'

@description('Also enable Defender for Storage. Off by default: the lab deploys no storage account of its own, so this only bills for whatever else lives in the subscription.')
param includeStorage bool = false

@description('true enables the plans (Standard tier); false sets them back to Free. Per-node charges stop at Free; findings already raised remain visible.')
param enabled bool = true

var tier = enabled ? 'Standard' : 'Free'

// subPlan is only valid alongside Standard, so the whole properties object
// switches rather than carrying a null.
resource servers 'Microsoft.Security/pricings@2024-01-01' = if (serversPlan != 'None') {
  name: 'VirtualMachines'
  properties: enabled
    ? { pricingTier: 'Standard', subPlan: serversPlan }
    : { pricingTier: 'Free' }
}

resource sql 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'SqlServers'
  properties: { pricingTier: tier }
}

resource keyVaults 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'KeyVaults'
  properties: { pricingTier: tier }
}

resource arm 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'Arm'
  properties: { pricingTier: tier }
}

resource storage 'Microsoft.Security/pricings@2024-01-01' = if (includeStorage) {
  name: 'StorageAccounts'
  properties: { pricingTier: tier }
}

output appliedTier string = tier
output plansTouched array = concat(
  serversPlan != 'None' ? ['VirtualMachines (${serversPlan})'] : [],
  ['SqlServers', 'KeyVaults', 'Arm'],
  includeStorage ? ['StorageAccounts'] : []
)
output billingReminder string = enabled
  ? 'These plans bill per node across the whole subscription, every hour, until disabled: redeploy with enabled=false.'
  : 'Plans set to Free. Per-node charges stop; findings already raised remain visible.'
