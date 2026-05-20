// Flex Consumption (FC1) Function App module.
//
// IMPORTANT — FC1 vs Linux Consumption (Y1) are completely different:
//   - Y1/Dynamic: CLI-created, WEBSITE_RUN_FROM_PACKAGE deployment, deprecated
//   - FC1/FlexConsumption: ARM-only creation, One Deploy (blob-based), modern
//
// This module uses Bicep's ARM API directly, which is equivalent to:
//   az rest --method PUT .../serverfarms (for the plan)
//   az rest --method PUT .../sites (for the app)
// This is the ONLY reliable way to create FC1 — the CLI flags silently fail (CLI v2.83.0).
//
// Reference: azure-flex-consumption-deployment-guide.md

param funcAppName string
param fcPlanName string
param storageAccountName string   // Must already exist with the deployment container
param location string
param tags object = {}

// Optional app settings — extend as needed per project
param sqlConnectionString string = ''
param aiProjectEndpoint string = ''
param blobStorageAccountName string = ''
param blobContainerName string = ''

// ---------------------------------------------------------------------------
// FC1 App Service Plan
// ---------------------------------------------------------------------------
// PITFALL: `az appservice plan create --sku FC1` silently creates the wrong plan type.
// Bicep uses the ARM API directly, which is reliable.
resource fcPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: fcPlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
    family: 'FC'
    size: 'FC1'
  }
  properties: {
    reserved: true  // Required for Linux-based plans
  }
}

// ---------------------------------------------------------------------------
// Flex Consumption Function App
// ---------------------------------------------------------------------------
// PITFALL: `az functionapp create --plan` ignores --plan on FC1 and silently
// places the app on the shared Y1/Dynamic plan. Bicep ARM is reliable.
resource funcApp 'Microsoft.Web/sites@2023-12-01' = {
  name: funcAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: fcPlan.id
    functionAppConfig: {
      deployment: {
        storage: {
          // One Deploy (blob-based) — replaces WEBSITE_RUN_FROM_PACKAGE (forbidden on FC1)
          type: 'blobContainer'
          value: 'https://${storageAccountName}.blob.core.windows.net/app-package-${funcAppName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        // PITFALL: Runtime is declared HERE, NOT in app settings.
        // Setting FUNCTIONS_WORKER_RUNTIME in app settings causes "malformed content"
        // deployment failures on FC1 — do not set it anywhere.
        name: 'node'
        version: '22'
      }
    }
  }
}

// ---------------------------------------------------------------------------
// App Settings
// ---------------------------------------------------------------------------
// PITFALL: Do NOT include FUNCTIONS_WORKER_RUNTIME — forbidden on FC1.
// PITFALL: Use AzureWebJobsStorage__accountName (double underscore, not single).
//          Double underscore = managed identity auth. The Function App MI must
//          have Storage Blob Data Owner on this storage account.
// PITFALL: Do NOT set WEBSITE_RUN_FROM_PACKAGE or WEBSITE_ENABLE_SYNC_UPDATE_SITE.
resource appSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: funcApp
  name: 'appsettings'
  properties: union(
    {
      AzureWebJobsStorage__accountName: storageAccountName
    },
    !empty(sqlConnectionString)      ? { SQL_CONNECTION_STRING: sqlConnectionString }           : {},
    !empty(aiProjectEndpoint)        ? { AI_PROJECT_ENDPOINT: aiProjectEndpoint }               : {},
    !empty(blobStorageAccountName)   ? { BLOB_STORAGE_ACCOUNT_NAME: blobStorageAccountName }   : {},
    !empty(blobContainerName)        ? { BLOB_CONTAINER_NAME: blobContainerName }               : {}
  )
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output funcAppName string = funcApp.name
output principalId string = funcApp.identity.principalId
output hostName string = funcApp.properties.defaultHostName

// ---------------------------------------------------------------------------
// IMPORTANT — deploying SP permission requirement:
// This module creates Microsoft.Authorization/roleAssignments resources (see below).
// The GitHub Actions SP must have BOTH:
//   - Contributor (resource creation)
//   - User Access Administrator (roleAssignments/write) at the RG scope
// Contributor alone is insufficient — the deployment will fail with a 403.
// Grant with: az role assignment create --assignee <SP_OID> --role "User Access Administrator"
//             --scope /subscriptions/{sub}/resourceGroups/{rg}
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Role assignments required after deployment (add to roleAssignments.bicep):
//
//   Function App MI → storageAccount
//     Role: Storage Blob Data Owner (b7e6dc6d-f1e8-4753-8033-0f276bb0955b)
//     Reason: host lease management + deployment blob read + user delegation SAS
//
//   Function App MI → AI Services (if used)
//     Role: Cognitive Services OpenAI User (5e0bd9bd-7b93-4f28-af87-19fc36ad61bd)
//
// GitHub Actions service principal → storageAccount
//     Role: Storage Blob Data Contributor
//     Reason: upload the deployment zip into app-package-{funcAppName} container
// ---------------------------------------------------------------------------
