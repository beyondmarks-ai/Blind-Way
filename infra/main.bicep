@description('Short product prefix used in globally unique resource names.')
param prefix string = 'blindway'

@description('Stable stamp used to create a fresh globally unique resource set after a failed deployment.')
param deploymentStamp string = 'v2'

@description('Primary region for API and data resources.')
param location string = resourceGroup().location

@description('Region for Azure Notification Hubs.')
param notificationLocation string = 'centralindia'

@description('Resource group containing the existing Azure OpenAI account.')
param azureOpenAiResourceGroup string = 'Beyond_Marks'

@description('Existing Azure OpenAI account name.')
param azureOpenAiAccountName string = 'Rakesh'

@description('Existing vision deployment name.')
param azureOpenAiDeployment string = 'gpt-5.1'

@description('Firebase project whose ID tokens are accepted by the API.')
param firebaseProjectId string = 'blind-way-beyondmarks-2026'

var suffix = take(uniqueString(subscription().id, resourceGroup().id, deploymentStamp), 8)
var compactPrefix = replace(prefix, '-', '')
var storageName = take('${compactPrefix}${suffix}', 24)
var functionName = '${prefix}-api-win-${suffix}'
var cosmosName = '${prefix}-db-${suffix}'
var keyVaultName = take('${prefix}-kv-${suffix}', 24)
var insightsName = '${prefix}-insights-${suffix}'
var logName = '${prefix}-logs-${suffix}'
var pubsubName = '${prefix}-realtime-${suffix}'
var notificationNamespaceName = '${prefix}-notify-${suffix}'
var notificationHubName = '${prefix}-android'

resource existingOpenAi 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  scope: resourceGroup(azureOpenAiResourceGroup)
  name: azureOpenAiAccountName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logName
  location: location
  properties: { retentionInDays: 30 }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${prefix}-consumption-win-${suffix}'
  location: location
  sku: { name: 'Y1', tier: 'Dynamic' }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    disableKeyBasedMetadataWriteAccess: true
    capabilities: [{ name: 'EnableServerless' }]
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
    publicNetworkAccess: 'Enabled'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'blindway'
  properties: { resource: { id: 'blindway' } }
}

resource items 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'items'
  properties: {
    resource: {
      id: 'items'
      partitionKey: { paths: ['/partitionKey'], kind: 'Hash' }
      defaultTtl: -1
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [{ path: '/*' }]
        excludedPaths: [{ path: '/"_etag"/?' }]
      }
    }
  }
}

resource pubsub 'Microsoft.SignalRService/webPubSub@2024-03-01' = {
  name: pubsubName
  location: location
  sku: { name: 'Free_F1', tier: 'Free', capacity: 1 }
  properties: {
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
    tls: { clientCertEnabled: false }
  }
}

resource notificationNamespace 'Microsoft.NotificationHubs/namespaces@2023-09-01' = {
  name: notificationNamespaceName
  location: notificationLocation
  sku: { name: 'Standard', tier: 'Standard' }
  properties: { namespaceType: 'NotificationHub' }
}

resource notificationHub 'Microsoft.NotificationHubs/namespaces/notificationHubs@2023-09-01' = {
  parent: notificationNamespace
  name: notificationHubName
  location: notificationLocation
  properties: {}
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    sku: { family: 'A', name: 'standard' }
    publicNetworkAccess: 'Enabled'
    accessPolicies: []
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionName
  location: location
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: false
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'AzureWebJobsFeatureFlags', value: 'EnableWorkerIndexing' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~22' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        { name: 'ENABLE_ORYX_BUILD', value: 'false' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}' }
        { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}' }
        { name: 'WEBSITE_CONTENTSHARE', value: take('${compactPrefix}${suffix}wincontent', 63) }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
        { name: 'FIREBASE_PROJECT_ID', value: firebaseProjectId }
        { name: 'ALLOW_DEBUG_AUTH', value: 'false' }
        { name: 'AZURE_OPENAI_ENDPOINT', value: existingOpenAi.properties.endpoint }
        { name: 'AZURE_OPENAI_DEPLOYMENT', value: azureOpenAiDeployment }
        { name: 'SARVAM_TTS_MODEL', value: 'bulbul:v3' }
        { name: 'SARVAM_TTS_SPEAKER', value: 'ritu' }
        { name: 'COSMOS_ENDPOINT', value: cosmos.properties.documentEndpoint }
        { name: 'COSMOS_DATABASE', value: 'blindway' }
        { name: 'WEB_PUBSUB_CONNECTION_STRING', value: pubsub.listKeys().primaryConnectionString }
        { name: 'WEB_PUBSUB_HUB', value: 'alerts' }
        { name: 'NOTIFICATION_HUB_NAME', value: notificationHub.name }
      ]
    }
  }
}

resource cosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, functionApp.id, 'data-contributor')
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmos.id
  }
}

output functionAppName string = functionApp.name
output storageAccountName string = storage.name
output functionPrincipalId string = functionApp.identity.principalId
output azureOpenAiResourceId string = existingOpenAi.id
output apiBaseUrl string = 'https://${functionApp.properties.defaultHostName}/api'
output cosmosAccountName string = cosmos.name
output keyVaultName string = keyVault.name
output notificationNamespaceName string = notificationNamespace.name
output notificationHubName string = notificationHub.name
output webPubSubName string = pubsub.name
