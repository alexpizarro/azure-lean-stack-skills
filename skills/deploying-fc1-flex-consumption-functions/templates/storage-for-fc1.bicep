// Reusable storage account module.
// Used by:
//   - functionApp.bicep: runtime host storage + deployment blob container
//   - Future: temporary image upload storage (add a second container)
//
// The Flex Consumption Function App authenticates via Managed Identity,
// so no connection string is needed — only the account name.

param storageAccountName string
param location string
param tags object = {}

// If provided, creates the deployment container expected by the FC1 runtime.
// Convention: 'app-package-{funcAppName}' (Azure Functions runtime requirement)
param funcAppName string = ''

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Deployment container for the Flex Consumption Function App.
// The runtime uploads the app zip here during deployment.
resource deployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (!empty(funcAppName)) {
  parent: blobService
  name: 'app-package-${funcAppName}'
  properties: {
    publicAccess: 'None'
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
