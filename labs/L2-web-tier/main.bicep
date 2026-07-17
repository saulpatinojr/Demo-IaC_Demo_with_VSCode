// ============================================================================
// L2 — Web Tier + Azure Firewall (builds on L1)
// Adds to L1's network: a web subnet in the spoke, 3 nginx VMs behind an
// INTERNAL load balancer, and an Azure Firewall in the hub. Inbound traffic
// enters through a firewall DNAT rule -> internal LB (this avoids the
// asymmetric-routing problem of a public LB + forced tunneling). Egress from
// the web subnet is forced through the firewall by a route table.
// Prerequisite: L1 must be deployed (same prefix).
// ============================================================================
targetScope = 'subscription'

@description('Same prefix used in L1.')
@maxLength(12)
param prefix string = 'iacdemo'

@description('Same region used in L1.')
param location string = 'eastus2'

@description('Resource group created by L1.')
param l1ResourceGroupName string = 'rg-${prefix}-l1'

@description('Admin username for the web VMs.')
param adminUsername string = 'azureuser'

@description('Admin password for the web VMs.')
@secure()
param adminPassword string

var rgName = 'rg-${prefix}-l2'
var hubVnetName = 'vnet-${prefix}-hub'
var spokeVnetName = 'vnet-${prefix}-spoke1'
var webSubnetPrefix = '10.1.1.0/24'
var ilbFrontendIp = '10.1.1.100'
var vmCount = 3

// cloud-init: install nginx and serve a page that names the VM (for the
// round-robin test).
var webCloudInit = base64('''
#cloud-config
packages:
  - nginx
runcmd:
  - echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
  - systemctl restart nginx
''')

resource l1Rg 'Microsoft.Resources/resourceGroups@2024-11-01' existing = {
  name: l1ResourceGroupName
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  scope: l1Rg
  name: hubVnetName
}

resource rg 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: rgName
  location: location
  tags: { lab: 'L2', demo: prefix }
}

// --- Firewall public IP (also the DNAT entry point for the web tier) ------
module fwPip 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  scope: rg
  name: 'l2-fw-pip'
  params: {
    name: 'pip-${prefix}-fw'
    location: location
    skuName: 'Standard'
  }
}

// --- Azure Firewall in L1's hub (AzureFirewallSubnet was reserved by L1) ---
module firewall 'br/public:avm/res/network/azure-firewall:0.10.1' = {
  scope: rg
  name: 'l2-firewall'
  params: {
    name: 'afw-${prefix}-hub'
    location: location
    virtualNetworkResourceId: hubVnet.id
    publicIPResourceID: fwPip.outputs.resourceId
    azureSkuTier: 'Standard'
    natRuleCollections: [
      {
        name: 'inbound-web'
        properties: {
          priority: 100
          action: { type: 'Dnat' }
          rules: [
            {
              name: 'http-to-ilb'
              protocols: ['TCP']
              sourceAddresses: ['*']
              destinationAddresses: [fwPip.outputs.ipAddress]
              destinationPorts: ['80']
              translatedAddress: ilbFrontendIp
              translatedPort: '80'
            }
          ]
        }
      }
    ]
    networkRuleCollections: [
      {
        name: 'allow-web-egress'
        properties: {
          priority: 200
          action: { type: 'Allow' }
          rules: [
            {
              name: 'https-and-http-out'
              protocols: ['TCP']
              sourceAddresses: ['10.1.0.0/16']
              destinationAddresses: ['*']
              destinationPorts: ['80', '443']
            }
          ]
        }
      }
      // Everything else outbound (ICMP, other ports) is denied by default —
      // that's the "blocked traffic" test in the lab guide.
    ]
  }
}

// --- NSG for the web subnet -------------------------------------------------
module webNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  scope: rg
  name: 'l2-web-nsg'
  params: {
    name: 'nsg-${prefix}-web'
    location: location
    securityRules: [
      {
        name: 'allow-http-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '10.0.0.0/8' // firewall SNAT + intra-VNet only
          destinationPortRange: '80'
          destinationAddressPrefix: webSubnetPrefix
        }
      }
    ]
  }
}

// --- Route table: force web-subnet egress through the firewall -------------
module webRouteTable 'br/public:avm/res/network/route-table:0.5.0' = {
  scope: rg
  name: 'l2-web-rt'
  params: {
    name: 'rt-${prefix}-web'
    location: location
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.outputs.privateIp
        }
      }
    ]
  }
}

// --- Add the web subnet to L1's spoke VNet (local module: AVM has no
//     standalone-subnet module) ----------------------------------------------
module webSubnet '../modules/subnet.bicep' = {
  scope: l1Rg
  name: 'l2-web-subnet'
  params: {
    vnetName: spokeVnetName
    subnetName: 'snet-web'
    addressPrefix: webSubnetPrefix
    networkSecurityGroupResourceId: webNsg.outputs.resourceId
    routeTableResourceId: webRouteTable.outputs.resourceId
  }
}

// --- Internal load balancer (Standard) --------------------------------------
module ilb 'br/public:avm/res/network/load-balancer:0.7.1' = {
  scope: rg
  name: 'l2-ilb'
  params: {
    name: 'lbi-${prefix}-web'
    location: location
    frontendIPConfigurations: [
      {
        name: 'frontend-web'
        subnetResourceId: webSubnet.outputs.subnetResourceId
        privateIPAddress: ilbFrontendIp
      }
    ]
    backendAddressPools: [
      { name: 'web-backend' }
    ]
    probes: [
      {
        name: 'http-probe'
        protocol: 'Http'
        port: 80
        requestPath: '/'
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-rule'
        frontendIPConfigurationName: 'frontend-web'
        backendAddressPoolName: 'web-backend'
        probeName: 'http-probe'
        protocol: 'Tcp'
        frontendPort: 80
        backendPort: 80
      }
    ]
  }
}

// --- 3 web VMs (nginx via cloud-init) ---------------------------------------
module webVms 'br/public:avm/res/compute/virtual-machine:0.22.2' = [
  for i in range(0, vmCount): {
    scope: rg
    name: 'l2-web-vm-${i}'
    params: {
      name: 'vm-${prefix}-web${i}'
      location: location
      osType: 'Linux'
      vmSize: 'Standard_B2s'
      availabilityZone: -1
      adminUsername: adminUsername
      adminPassword: adminPassword
      disablePasswordAuthentication: false
      customData: webCloudInit
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
              subnetResourceId: webSubnet.outputs.subnetResourceId
              loadBalancerBackendAddressPools: [
                { id: '${ilb.outputs.resourceId}/backendAddressPools/web-backend' }
              ]
            }
          ]
        }
      ]
    }
  }
]

output resourceGroupName string = rgName
output firewallPublicIp string = fwPip.outputs.ipAddress
output testUrl string = 'http://${fwPip.outputs.ipAddress}/'
output webVmNames array = [for i in range(0, vmCount): webVms[i].outputs.name]
