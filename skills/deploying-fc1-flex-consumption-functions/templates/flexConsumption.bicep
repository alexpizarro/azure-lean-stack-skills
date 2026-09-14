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
// Reference: ../references/arm-rest-walkthrough.md (same PUT bodies via az rest).

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

@description('Instance memory: 512 (0.25 vCPU, cheapest), 2048 (1 vCPU, default), 4096 (2 vCPU).')
@allowed([512, 2048, 4096])
param instanceMemoryMB int = 2048

@description('Create the Storage Blob Data Owner assignment for the app MI on the host storage account. Needs the deploying SP to hold User Access Administrator; set false and assign out-of-band if the CI SP is Contributor-only.')
param assignHostStorageRole bool = true

// ---------------------------------------------------------------------------
// FC1 App Service Plan
// ---------------------------------------------------------------------------
// PITFALL: `az appservice plan create --sku FC1` silently creates the wrong plan type.
// Bicep uses the ARM API directly, which is reliable.
resource fcPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
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
resource funcApp 'Microsoft.Web/sites@2024-04-01' = {
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
        // alwaysReady: [] = no always-on charge (default). Add
        // [{ name: 'http', instanceCount: 1 }] only if first-hit latency proves unacceptable —
        // always-ready instances bill continuously (cost-guardrails Guardrail #9).
        alwaysReady: []
        maximumInstanceCount: 100
        // 512 MB is GA and the cheapest size (0.25 vCPU); 2048 MB (1 vCPU) is the safe default
        // for Node + mssql. Bump to 4096 only for memory-heavy work.
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        // PITFALL: Runtime is declared HERE, NOT in app settings.
        // Setting FUNCTIONS_WORKER_RUNTIME in app settings causes "malformed content"
        // deployment failures on FC1 — do not set it anywhere.
        name: 'node'
        version: '22'   // Node 24 is also GA on Flex Consumption; 22 stays LTS until 2027-04
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
resource appSettings 'Microsoft.Web/sites/config@2024-04-01' = {
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
// Host storage RBAC — the runtime uses AzureWebJobsStorage__accountName (identity
// auth), so the MI MUST hold Storage Blob Data Owner on the host storage account
// before the host first starts (lease + deployment blob + user-delegation SAS).
// Toggle off (assignHostStorageRole=false) and assign out-of-band once if the CI
// SP lacks roleAssignments/write. Propagation can take 3–10 min.
// ---------------------------------------------------------------------------
resource hostStorage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

resource hostStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignHostStorageRole) {
  name: guid(hostStorage.id, funcApp.id, storageBlobDataOwnerRoleId)
  scope: hostStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: funcApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output funcAppName string = funcApp.name
output principalId string = funcApp.identity.principalId
output hostName string = funcApp.properties.defaultHostName

// ---------------------------------------------------------------------------
// IMPORTANT — deploying SP permission requirement:
// With assignHostStorageRole=true (default) this module creates a
// Microsoft.Authorization/roleAssignments resource, so the GitHub Actions SP must have BOTH:
//   - Contributor (resource creation)
//   - User Access Administrator (roleAssignments/write) at the RG scope
// Contributor alone fails with 403. Grant with:
//   az role assignment create --assignee <SP_OID> --role "User Access Administrator" \
//     --scope /subscriptions/{sub}/resourceGroups/{rg}
// or set assignHostStorageRole=false and run the assignment once from an owner session.
//
// Other assignments this module does NOT create (add in main.bicep or out-of-band):
//   Function App MI → AI Services (if used): Cognitive Services OpenAI User (5e0bd9bd-7b93-4f28-af87-19fc36ad61bd)
//   GitHub Actions SP → storageAccount: Storage Blob Data Contributor (upload the deploy zip)
//   Data-plane SQL/Blob roles: see securing-azure-sql-and-storage-with-managed-identity
// ---------------------------------------------------------------------------
