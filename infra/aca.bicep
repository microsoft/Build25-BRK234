param name string
param location string = resourceGroup().location
param tags object = {}

param identityName string
param containerAppsEnvironmentName string
param containerRegistryName string
param serviceName string = 'aca'
param exists bool
param openAiDeploymentName string
param openAiResourceName string
param openAiEndpoint string
param useKeylessAuth bool = true
param useLogin bool = true
param usePrivateIngress bool = true

resource acaIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource openAi 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: openAiResourceName
}


module app 'core/host/container-app-upsert.bicep' = {
  name: '${serviceName}-container-app-module'
  params: {
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    identityName: acaIdentity.name
    exists: exists
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    ingressEnabled: true
    secrets: [
      // Include OpenAI key if keyless auth is not used
      (!useKeylessAuth) ? {
        name: 'azure-openai-key'
        value: openAi.listKeys().key1
      } : null
      // Include login secret if useLogin is true
      (useLogin) ? {
        name: 'override-use-mi-fic-assertion-client-id'
        value: acaIdentity.properties.clientId
      } : null
    ]
    env: [
      useKeylessAuth ? {
        name: 'AZURE_OPENAI_KEY_OVERRIDE'
        value: ''
      } : {
        name: 'AZURE_OPENAI_KEY_OVERRIDE'
        secretRef: 'azure-openai-key'
      }
      {
        name: 'AZURE_OPENAI_CHAT_DEPLOYMENT'
        value: openAiDeploymentName
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: openAiEndpoint
      }
      {
        name: 'RUNNING_IN_PRODUCTION'
        value: 'true'
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: acaIdentity.properties.clientId
      }
    ]
    targetPort: 50505
  }
}

output identityPrincipalId string = acaIdentity.properties.principalId
output name string = app.outputs.name
output hostName string = app.outputs.hostName
output uri string = app.outputs.uri
output imageName string = app.outputs.imageName
