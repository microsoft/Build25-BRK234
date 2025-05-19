targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name which is used to generate a short unique hash for each resource')
param name string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

param acaExists bool = false

@description('Location for the OpenAI resource group')
@allowed([ 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'switzerlandnorth', 'uksouth', 'japaneast', 'northcentralus', 'australiaeast', 'swedencentral' ])
@metadata({
  azd: {
    type: 'location'
  }
})
param openAiResourceLocation string

@description('Flag to decide whether to create a role assignment for the user and app')
param useKeylessAuth bool = true

@description('Flag to decide whether to add user login to the container app')
param useLogin bool = true

@description('Whether to use a custom RAI policy with stricter rules')
param useStrictRaiPolicy bool = true

@description('Flag to enable or disable the virtual network feature')
param useVnet bool = true

@description('Flag to enable or disable monitoring resources')
param useMonitoring bool = true

@description('Service Management Reference for the Entra app registration')
param serviceManagementReference string = ''

@description('Whether the deployment is running on GitHub Actions')
param runningOnGh string = ''
 
@description('Flag to enable or disable public ingress')
param usePrivateIngress bool = true

@description('Flag to enable or disable Azure Front Door')
param useFrontDoor bool = true

var resourceToken = toLower(uniqueString(subscription().id, name, location))
var tags = { 'azd-env-name': name }

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${name}-rg'
  location: location
  tags: tags
}

var prefix = '${name}-${resourceToken}'

var openAiDeploymentName = 'gpt-4o-mini'

var issuer = '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'


module openAi 'br/public:avm/res/cognitive-services/account:0.7.2' = {
  name: 'openai'
  scope: resourceGroup
  params: {
    name: '${resourceToken}-cog'
    location: !empty(openAiResourceLocation) ? openAiResourceLocation : location
    tags: tags
    kind: 'OpenAI'
    customSubDomainName: '${resourceToken}-cog'
    publicNetworkAccess: useVnet ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: useVnet ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
    sku: 'S0'
    diagnosticSettings: useMonitoring ? [
      {
        name: 'customSetting'
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
      }
    ] : []
    deployments: [
      {
        name: openAiDeploymentName
        model: {
          format: 'OpenAI'
          name: 'gpt-4o-mini'
          version: '2024-07-18'
        }
        sku: {
          name: 'GlobalStandard'
          capacity: 30
        }
        raiPolicyName: useStrictRaiPolicy ? 'StrictRaiPolicy' : 'Microsoft.DefaultV2'
      }
    ]
    disableLocalAuth: useKeylessAuth
  }
}


module raiPolicy 'raipolicy.bicep' = if (useStrictRaiPolicy) {
  name: 'rai-policy'
  scope: resourceGroup
  params: {
    name: 'StrictRaiPolicy'
    openAiResourceName: openAi.outputs.name
  }
}

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.7.0' = if (useMonitoring) {
  name: 'loganalytics'
  scope: resourceGroup
  params: {
    name: '${prefix}-loganalytics'
    location: location
    tags: tags
    skuName: 'PerGB2018'
    dataRetention: 30
    publicNetworkAccessForIngestion: useVnet ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: useVnet ? 'Disabled' : 'Enabled'
    useResourcePermissions: true
  }
}

// https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration?tabs=consumption-only
module containerAppsNSG 'br/public:avm/res/network/network-security-group:0.5.1' = if (useVnet) {
  name: 'containerAppsNSG'
  scope: resourceGroup
  params: {
    name: '${prefix}-container-apps-nsg'
    location: location
    tags: tags
    securityRules: concat(
      usePrivateIngress ? [
        {
          name: 'AllowHttpsInbound'
          properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            sourceAddressPrefix: 'Internet'
            destinationPortRange: '443'
            destinationAddressPrefix: '*'
            access: 'Allow'
            priority: 100
            direction: 'Inbound'
          }
        }
      ] : []
    )
  }
}

module privateEndpointsNSG 'br/public:avm/res/network/network-security-group:0.5.1' = if (useVnet) {
  name: 'privateEndpointsNSG'
  scope: resourceGroup
  params: {
    name: '${prefix}-private-endpoints-nsg'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'AllowVnetInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyInternetInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVnetOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowDnsOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '53'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyInternetOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Deny'
          priority: 4096
          direction: 'Outbound'
        }
      }
    ]
  }
}


module ddosProtectionPlan 'br/public:avm/res/network/ddos-protection-plan:0.3.1' = if (useVnet && useFrontDoor) {
  name: 'ddosProtectionPlanDeployment'
  scope: resourceGroup
  params: {
    name: '${prefix}-ddos-protection-plan'
    location: location
  }
}

// Virtual network for all resources
module virtualNetwork 'br/public:avm/res/network/virtual-network:0.6.1' = if (useVnet) {
  name: 'vnet'
  scope: resourceGroup
  params: {
    name: '${prefix}-vnet'
    location: location
    tags: tags
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    // DDOS protection is only needed when a subnet has a "public IP"
    ddosProtectionPlanResourceId: useFrontDoor? ddosProtectionPlan.outputs.resourceId : null
    subnets: [
      {
        name: 'container-apps-subnet'
        addressPrefix: '10.0.0.0/21'
        networkSecurityGroupResourceId: containerAppsNSG.outputs.resourceId
        delegation: 'Microsoft.App/environments'
      }
      {
        name: 'private-endpoints-subnet'
        addressPrefix: '10.0.8.0/24'
        privateEndpointNetworkPolicies: 'Enabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
        networkSecurityGroupResourceId: privateEndpointsNSG.outputs.resourceId
      }
      {
        name: 'GatewaySubnet' // Required name for Gateway subnet
        addressPrefix: '10.0.255.0/27' // Using a /27 subnet size which is minimal required size for gateway subnet
      }
      {
        name: 'dns-resolver-subnet' // Dedicated subnet for Azure Private DNS Resolver
        addressPrefix: '10.0.11.0/28' // Original value kept as requested
        delegation: 'Microsoft.Network/dnsResolvers'
      }
    ]
  }
}

// Azure OpenAI Private DNS Zone
module openAiPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet) {
  name: 'openai-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.openai.azure.com'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Log Analytics Private DNS Zone
module logAnalyticsPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet && useMonitoring) {
  name: 'log-analytics-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.oms.opinsights.azure.com'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Additional Log Analytics Private DNS Zone for query endpoint
module logAnalyticsQueryPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet && useMonitoring) {
  name: 'log-analytics-query-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.ods.opinsights.azure.com'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Additional Log Analytics Private DNS Zone for agent service
module logAnalyticsAgentPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet && useMonitoring) {
  name: 'log-analytics-agent-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.agentsvc.azure-automation.net'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Azure Monitor Private DNS Zone
module monitorPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet && useMonitoring) {
  name: 'monitor-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.monitor.azure.com'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Storage Blob Private DNS Zone for Log Analytics solution packs
module blobPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet && useMonitoring) {
  name: 'blob-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.blob.core.windows.net'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Azure Container Registry Private DNS Zone
module acrPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet) {
  name: 'acr-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.azurecr.io'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Container Apps Private DNS Zone
module containerAppsPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (useVnet) {
  name: 'container-apps-dns-zone'
  scope: resourceGroup
  params: {
    name: 'privatelink.${location}.azurecontainerapps.io'
    tags: tags
    virtualNetworkLinks: [
      {
        registrationEnabled: false
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}

// Container Apps Environment Private Endpoint
// https://learn.microsoft.com/azure/container-apps/how-to-use-private-endpoint
module containerAppsEnvironmentPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (useVnet) {
  name: 'containerAppsEnvironmentPrivateEndpointDeployment'
  scope: resourceGroup
  params: {
    name: '${prefix}-containerappsenv-pe'
    location: location
    tags: tags
    subnetResourceId: virtualNetwork.outputs.subnetResourceIds[1]
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: containerAppsPrivateDnsZone.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: '${prefix}-container-apps-env-pe'
        properties: {
          groupIds: [
            'managedEnvironments'
          ]
          privateLinkServiceId: containerApps.outputs.environmentId
        }
      }
    ]
  }
}

module privateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (useVnet) {
  name: 'privateEndpointDeployment'
  scope: resourceGroup
  params: {
    name: '${prefix}-openai-pe'
    location: location
    tags: tags
    subnetResourceId: virtualNetwork.outputs.subnetResourceIds[1]
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: openAiPrivateDnsZone.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: '${prefix}-openai-pe'
        properties: {
          groupIds: [
            'account'
          ]
          privateLinkServiceId: openAi.outputs.resourceId
        }
      }
    ]
  }
}

// Azure Monitor Private Link Scope
module monitorPrivateLinkScope 'br/public:avm/res/insights/private-link-scope:0.7.1' = if (useVnet && useMonitoring) {
  name: 'monitor-private-link-scope'
  scope: resourceGroup
  params: {
    name: '${prefix}-ampls'
    location: 'global'
    tags: tags
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
    scopedResources: [
      {
        name: 'loganalytics-scoped-resource'
        linkedResourceId: logAnalyticsWorkspace.outputs.resourceId
      }
    ]
    privateEndpoints: [
      {
        name: 'loganalytics-private-endpoint'
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[1]
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: monitorPrivateDnsZone.outputs.resourceId
            }
            {
              privateDnsZoneResourceId: logAnalyticsPrivateDnsZone.outputs.resourceId
            }
            {
              privateDnsZoneResourceId: logAnalyticsQueryPrivateDnsZone.outputs.resourceId
            }
            {
              privateDnsZoneResourceId: logAnalyticsAgentPrivateDnsZone.outputs.resourceId
            }
            {
              privateDnsZoneResourceId: blobPrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
  }
}

// Container apps host (including container registry)
module containerApps 'core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: resourceGroup
  params: {
    name: 'app'
    location: location
    tags: tags
    containerAppsEnvironmentName: '${prefix}-containerapps-env'
    containerRegistryName: '${replace(prefix, '-', '')}registry'
    logAnalyticsWorkspaceName: useMonitoring ? logAnalyticsWorkspace.outputs.name : ''
    // Reference the virtual network only if useVnet is true
    subnetResourceId: useVnet ? virtualNetwork.outputs.subnetResourceIds[0] : ''
    vnetName: useVnet ? virtualNetwork.outputs.name : ''
    subnetName: useVnet ? virtualNetwork.outputs.subnetNames[0] : ''
    usePrivateIngress: usePrivateIngress
  }
}

// Container Registry Private Endpoint
module acrPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (useVnet) {
  name: 'acrPrivateEndpointDeployment'
  scope: resourceGroup
  params: {
    name: '${prefix}-acr-pe'
    location: location
    tags: tags
    subnetResourceId: virtualNetwork.outputs.subnetResourceIds[1]
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: acrPrivateDnsZone.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: '${prefix}-acr-pe'
        properties: {
          groupIds: [
            'registry'
          ]
          privateLinkServiceId: containerApps.outputs.registryId
        }
      }
    ]
  }
}

module virtualNetworkGateway 'br/public:avm/res/network/virtual-network-gateway:0.6.1' = if (useVnet) {
  name: 'virtualNetworkGatewayDeployment'
  scope: resourceGroup
  params: {
    name: '${prefix}-vnet-gateway'
    clusterSettings: {
      clusterMode: 'activePassiveNoBgp'
    }
    gatewayType: 'Vpn'
    virtualNetworkResourceId: virtualNetwork.outputs.resourceId
    vpnGatewayGeneration: 'Generation2'
    vpnClientAddressPoolPrefix: '172.16.201.0/24'
    skuName: 'VpnGw2AZ' // https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpngateways
    vpnClientAadConfiguration: {
      aadAudience: 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'
      aadIssuer: 'https://sts.windows.net/${tenant().tenantId}/'
      aadTenant: '${environment().authentication.loginEndpoint}${tenant().tenantId}'
      vpnAuthenticationTypes: [
        'AAD'
      ]
      vpnClientProtocols: [
        'OpenVPN'
      ]
    }
  }
}

// Based on https://luke.geek.nz/azure/azure-point-to-site-vpn-and-private-dns-resolver/
// Manual step required of updating azurevpnconfig.xml to use the correct DNS server IP address
module dnsResolver 'br/public:avm/res/network/dns-resolver:0.5.3' = if (useVnet) {
  name: 'dnsResolverDeployment'
  scope: resourceGroup
  params: {
    name: '${prefix}-dns-resolver'
    location: location
    virtualNetworkResourceId: virtualNetwork.outputs.resourceId
    inboundEndpoints: [
      {
        name: 'inboundEndpoint'
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[3]
      }
    ]
  }
}

// Container app frontend
module aca 'aca.bicep' = {
  name: 'aca'
  scope: resourceGroup
  params: {
    name: replace('${take(prefix,19)}-ca', '--', '-')
    location: location
    tags: tags
    identityName: '${prefix}-id-aca'
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    openAiDeploymentName: openAiDeploymentName
    openAiEndpoint: openAi.outputs.endpoint
    openAiResourceName: openAi.outputs.name
    exists: acaExists
    useKeylessAuth: useKeylessAuth
    useLogin: useLogin
    usePrivateIngress: usePrivateIngress
  }
}

module openAiRoleUser 'core/security/role.bicep' = if (useKeylessAuth && empty(runningOnGh)) {
  scope: resourceGroup
  name: 'openai-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
    principalType: 'User'
  }
}

module openAiRoleBackend 'core/security/role.bicep' = if (useKeylessAuth) {
  scope: resourceGroup
  name: 'openai-role-backend'
  params: {
    principalId: aca.outputs.identityPrincipalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'  // Cognitive Services OpenAI User
    principalType: 'ServicePrincipal'
  }
}

module registration 'appregistration.bicep' = if (useLogin) {
  name: 'reg'
  scope: resourceGroup
  params: {
    clientAppName: '${prefix}-entra-client-app'
    clientAppDisplayName: 'Secure Demo Entra Client App'
    webAppEndpoint: aca.outputs.uri
    frontDoorEndpoint: useFrontDoor ? 'https://${profile.outputs.frontDoorEndpointHostNames[0]}' : ''
    webAppIdentityId: aca.outputs.identityPrincipalId
    issuer: issuer
    serviceManagementReference: serviceManagementReference
  }
}

module appupdate 'appupdate.bicep' = if (useLogin) {
  name: 'appupdate'
  scope: resourceGroup
  params: {
    containerAppName: aca.outputs.name
    clientId: registration.outputs.clientAppId
    openIdIssuer: issuer
    includeTokenStore: false
    forwardHostHeader: useFrontDoor
  }
}

module frontDoorWebApplicationFirewallPolicy 'br/public:avm/res/network/front-door-web-application-firewall-policy:0.3.2' = if (useFrontDoor) {
  name: 'frontDoorWebApplicationFirewallPolicyDeployment'
  scope: resourceGroup
  params: {
    name: '${replace(prefix, '-', '')}frontdoorwafpolicy'
    sku: 'Premium_AzureFrontDoor'
    customRules: {}
  }
}

module profile 'br/public:avm/res/cdn/profile:0.12.3' = if (useFrontDoor) {
  name: 'frontdoor'
  scope: resourceGroup
  params: {
    name: '${prefix}-frontdoor'
    location: 'global'
    sku: 'Premium_AzureFrontDoor'
    afdEndpoints: [
      {
        name: '${prefix}-frontdoor-endpoint'
        enabledState: 'Enabled'
        routes: [
          {
            name: '${prefix}-frontdoor-route'
            originGroupName: '${prefix}-frontdoor-origin-group'
            supportedProtocols: [
              'Http'
              'Https'
            ]
            patternsToMatch: [
              '/*'
            ]
            forwardingProtocol: 'MatchRequest'
            linkToDefaultDomain: 'Enabled'
            httpsRedirect: 'Enabled'
          }
        ]
      }
    ]
    originGroups: [
      {
        name: '${prefix}-frontdoor-origin-group'
        loadBalancingSettings: {
          additionalLatencyInMilliseconds: 50
          sampleSize: 4
          successfulSamplesRequired: 3
        }
        origins: [
          {
            name: 'aca-origin'
            hostName: aca.outputs.hostName
            originHostHeader: aca.outputs.hostName
            priority: 1
            weight: 500
            sharedPrivateLinkResource: {
              groupId: 'managedEnvironments'
              privateLink: {
                id: containerApps.outputs.environmentId
              }
              privateLinkLocation: location
              requestMessage: 'AFD Private Link Request'
              status: 'Approved'
            }
          }
        ]
      }
    ]
    securityPolicies: [
      {
        name: '${prefix}-frontdoor-security-policy'
        associations: [
          {
            domains: [
              {
                id: resourceId(
                  subscription().subscriptionId,
                  resourceGroup.name,
                  'Microsoft.Cdn/profiles/afdEndpoints',
                  '${prefix}-frontdoor',
                  '${prefix}-frontdoor-endpoint'
                )
              }
            ]
            patternsToMatch: [
              '/*'
            ]
          }
        ]
        wafPolicyResourceId: frontDoorWebApplicationFirewallPolicy.outputs.resourceId
      }
    ]
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroup.name

output AZURE_OPENAI_CHAT_DEPLOYMENT string = openAiDeploymentName
output AZURE_OPENAI_ENDPOINT string = openAi.outputs.endpoint
output AZURE_OPENAI_RESOURCE string = openAi.outputs.name
output AZURE_OPENAI_RESOURCE_LOCATION string = openAi.outputs.location
output USE_KEYLESS_AUTH string = useKeylessAuth ? 'true' : 'false'

output SERVICE_ACA_IDENTITY_PRINCIPAL_ID string = aca.outputs.identityPrincipalId
output SERVICE_ACA_NAME string = aca.outputs.name
output SERVICE_ACA_URI string = aca.outputs.uri
output SERVICE_ACA_IMAGE_NAME string = aca.outputs.imageName

output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName

output AZURE_FRONTDOOR_ENDPOINT string = useFrontDoor ? profile.outputs.frontDoorEndpointHostNames[0] : ''

// VPN Configuration Download Link with direct access to the point-to-site configuration page
output AZURE_VPN_CONFIG_DOWNLOAD_LINK string = useVnet ? 'https://portal.azure.com/#@${tenant().tenantId}/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup.name}/providers/Microsoft.Network/virtualNetworkGateways/${prefix}-vnet-gateway/pointtositeconfiguration' : ''
