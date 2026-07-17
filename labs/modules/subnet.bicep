// Adds (or updates) a subnet on an EXISTING virtual network in another lab's
// resource group. Kept as a local module because AVM modules manage whole
// VNets — there is no AVM module for a standalone subnet on an existing VNet.
param vnetName string
param subnetName string
param addressPrefix string
param networkSecurityGroupResourceId string = ''
param routeTableResourceId string = ''

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: addressPrefix
    networkSecurityGroup: empty(networkSecurityGroupResourceId) ? null : { id: networkSecurityGroupResourceId }
    routeTable: empty(routeTableResourceId) ? null : { id: routeTableResourceId }
  }
}

output subnetResourceId string = subnet.id
