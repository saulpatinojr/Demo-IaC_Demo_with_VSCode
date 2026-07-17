// ============================================================================
// L1 — Hub & Spoke Connectivity
// Deploys: hub VNet (Bastion + reserved firewall subnet), spoke VNet (peered),
// and one Linux VM in the spoke. Built entirely from Azure Verified Modules.
// L2 builds on top of this deployment — do not tear it down between labs.
// ============================================================================
targetScope = 'subscription'

@description('Prefix used for all resource names, e.g. "iacdemo".')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Azure region for all L1 resources.')
param location string = 'eastus2'

@description('Admin username for the test VM.')
param adminUsername string = 'azureuser'

@description('Admin password for the test VM (use a strong throwaway password — this is a demo).')
@secure()
param adminPassword string

var rgName = 'rg-${prefix}-l1'
var hubVnetName = 'vnet-${prefix}-hub'
var spokeVnetName = 'vnet-${prefix}-spoke1'

resource rg 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: rgName
  location: location
  tags: { lab: 'L1', demo: prefix }
}

// --- Hub VNet: Bastion subnet now, AzureFirewallSubnet reserved for L2 -----
module hubVnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  scope: rg
  name: 'l1-hub-vnet'
  params: {
    name: hubVnetName
    location: location
    addressPrefixes: ['10.0.0.0/16']
    subnets: [
      { name: 'AzureBastionSubnet', addressPrefix: '10.0.0.0/26' }
      { name: 'AzureFirewallSubnet', addressPrefix: '10.0.1.0/26' } // used by L2
    ]
  }
}

// --- Spoke VNet: workload subnet now, web subnet added by L2 ---------------
module spokeVnet 'br/public:avm/res/network/virtual-network:0.9.0' = {
  scope: rg
  name: 'l1-spoke-vnet'
  params: {
    name: spokeVnetName
    location: location
    addressPrefixes: ['10.1.0.0/16']
    subnets: [
      { name: 'snet-workload', addressPrefix: '10.1.0.0/24' }
    ]
    // Bidirectional peering — the module creates the reverse peering for us.
    peerings: [
      {
        remoteVirtualNetworkResourceId: hubVnet.outputs.resourceId
        allowForwardedTraffic: true
        remotePeeringEnabled: true
        remotePeeringAllowForwardedTraffic: true
      }
    ]
  }
}

// --- Bastion (Basic) — browser-based SSH, no public IP on the VM ----------
// NOTE: a VPN Gateway is the "real world" hybrid entry point, but it takes
// 30–45 minutes to deploy, so this demo uses Bastion instead. The equivalent
// gateway deployment is shown (commented) at the bottom of this file.
module bastion 'br/public:avm/res/network/bastion-host:0.8.2' = {
  scope: rg
  name: 'l1-bastion'
  params: {
    name: 'bas-${prefix}-hub'
    location: location
    virtualNetworkResourceId: hubVnet.outputs.resourceId
    skuName: 'Basic'
  }
}

// --- One small Linux VM in the spoke ---------------------------------------
module testVm 'br/public:avm/res/compute/virtual-machine:0.22.2' = {
  scope: rg
  name: 'l1-test-vm'
  params: {
    name: 'vm-${prefix}-test'
    location: location
    osType: 'Linux'
    vmSize: 'Standard_B2s'
    availabilityZone: -1
    adminUsername: adminUsername
    adminPassword: adminPassword
    disablePasswordAuthentication: false
    imageReference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      managedDisk: { storageAccountType: 'Standard_LRS' }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: spokeVnet.outputs.subnetResourceIds[0]
          }
        ]
      }
    ]
  }
}

output resourceGroupName string = rgName
output hubVnetId string = hubVnet.outputs.resourceId
output spokeVnetId string = spokeVnet.outputs.resourceId
output vmName string = testVm.outputs.name

// ============================================================================
// OPTIONAL — the "real world" VPN Gateway (slow to deploy; not used in demo):
//
// module vpnGateway 'br/public:avm/res/network/virtual-network-gateway:<ver>' = {
//   scope: rg
//   name: 'l1-vpn-gateway'
//   params: {
//     name: 'vgw-${prefix}-hub'
//     location: location
//     clusterSettings: { clusterMode: 'activePassiveNoBgp' }
//     gatewayType: 'Vpn'
//     skuName: 'VpnGw1'
//     vpnType: 'RouteBased'
//     virtualNetworkResourceId: hubVnet.outputs.resourceId
//   }
// }
// (also requires a "GatewaySubnet" in the hub VNet)
// ============================================================================
