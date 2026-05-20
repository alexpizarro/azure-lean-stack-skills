// Storage account with cost-optimised defaults:
//   - Standard_LRS (cheapest replication)
//   - Hot access tier (new blobs)
//   - TLS 1.2 minimum
//   - Lifecycle rules: delete temp blobs at 7d, age content Hot → Cool@60d → Cold@180d
//   - CORS configured for SPA uploads + Range reads
//   - Per-container public access (most private; opt-in branding container public-read)

param name string
param location string
param tags object = {}

@description('Origins allowed by CORS (browser uploads + Range reads).')
param corsAllowedOrigins array = ['http://localhost:5173']

@description('Prefixes treated as temp — auto-deleted after tempRetentionDays.')
param tempPrefixes array = ['incoming/', 'tmp/']

@description('Days before temp blobs are deleted.')
param tempRetentionDays int = 7

@description('Prefixes treated as ageing content — tiered through Hot → Cool → Cold.')
param contentPrefixes array = ['videos/', 'images/']

@description('Days before ageing content is moved to Cool tier.')
param tierToCoolDays int = 60

@description('Days before ageing content is moved to Cold tier.')
param tierToColdDays int = 180

@description('Whether to expose a public-read "branding" container alongside the private ones.')
param createBrandingContainer bool = false

@description('Additional private container names to create.')
param privateContainers array = ['data']

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    // Only enable account-level public access if we actually create a public container.
    allowBlobPublicAccess: createBrandingContainer
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: corsAllowedOrigins
          allowedMethods: ['GET', 'PUT', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']        // required for Range responses
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

// Always-create temp containers (private)
resource tempContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for prefix in tempPrefixes: {
  parent: blobService
  name: replace(prefix, '/', '')
  properties: { publicAccess: 'None' }
}]

// Private content containers
resource privateContainerResources 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in privateContainers: {
  parent: blobService
  name: c
  properties: { publicAccess: 'None' }
}]

// Optional public-read branding container
resource brandingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = if (createBrandingContainer) {
  parent: blobService
  name: 'branding'
  properties: { publicAccess: 'Blob' }
}

// Lifecycle policy
resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'delete-stale-temp-blobs'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: tempPrefixes
            }
            actions: {
              baseBlob: { delete: { daysAfterModificationGreaterThan: tempRetentionDays } }
            }
          }
        }
        {
          enabled: true
          name: 'tier-aging-content'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: contentPrefixes
            }
            actions: {
              baseBlob: {
                // Hot → Cool → Cold. Never Archive — rehydration takes hours.
                tierToCool: { daysAfterModificationGreaterThan: tierToCoolDays }
                tierToCold: { daysAfterModificationGreaterThan: tierToColdDays }
              }
            }
          }
        }
      ]
    }
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
