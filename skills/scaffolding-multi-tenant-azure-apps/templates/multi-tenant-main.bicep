targetScope = 'subscription'

// ============================================================================
// Multi-tenant root — one RG per tenant on a shared subscription.
// The 'tenant' parameter drives the RG name and every resource name.
// Default value preserves byte-identical names from a single-tenant origin so
// the first deploy of an existing project needs no migration.
// ============================================================================

@description('Deployment environment.')
@allowed(['test', 'prod'])
param environmentName string

@description('Azure region for data resources (RG, SQL, Storage, ACA).')
param location string = 'australiaeast'

// SWA is a global CDN service — australiaeast isn't supported.
// Set to eastasia for AU proximity.
var swaLocation = 'eastasia'

@description('Tenant slug — drives the RG and every resource name. Default matches the original single-tenant naming so existing deploys are byte-identical.')
param tenant string = 'acme-default'

@description('Storage account name override (no hyphens, ≤24 chars). Empty = derive from tenant.')
param storageAccountName string = ''

// Optional toggles — same pattern as single-tenant scaffolding skill
param deploySql bool = true
param deployStorage bool = false
param deployObservability bool = false

@secure()
@description('SQL admin password — required when deploySql=true.')
param sqlAdminPassword string = ''

@description('Owner email for alerts (when deployObservability=true).')
param alertEmail string = ''

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------
var rgName        = '${tenant}-rg-${environmentName}'
var swaName       = '${tenant}-swa-${environmentName}'
var sqlServerName = '${tenant}-sql-${environmentName}'
var sqlDbName     = '${tenant}-db-${environmentName}'

var derivedStorageName = toLower(replace('${tenant}store${environmentName}', '-', ''))
var actualStorageName  = empty(storageAccountName) ? derivedStorageName : storageAccountName

var tags = {
  tenant: tenant
  environment: environmentName
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------
module rg 'modules/resourceGroup.bicep' = {
  name: 'deploy-rg-${environmentName}'
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Static Web App (always)
// ---------------------------------------------------------------------------
module swa 'modules/staticWebApp.bicep' = {
  name: 'deploy-swa-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    name: swaName
    location: swaLocation
    skuName: environmentName == 'prod' ? 'Standard' : 'Free'
    sqlConnectionString: deploySql ? sqlConnectionString : ''
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// SQL (optional)
// ---------------------------------------------------------------------------
module sql 'modules/sqlServer.bicep' = if (deploySql) {
  name: 'deploy-sql-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    serverName: sqlServerName
    databaseName: sqlDbName
    location: location
    administratorLogin: 'sqladmin'
    administratorLoginPassword: sqlAdminPassword
    tags: tags
  }
}

var sqlConnectionString = deploySql
  ? 'Server=tcp:${sql!.outputs.serverFqdn},1433;Database=${sqlDbName};User Id=sqladmin;Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  : ''

// ---------------------------------------------------------------------------
// Storage (optional)
// ---------------------------------------------------------------------------
module storage 'modules/storageAccount.bicep' = if (deployStorage) {
  name: 'deploy-storage-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    name: actualStorageName
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Observability (optional)
// ---------------------------------------------------------------------------
module observability 'modules/applicationInsights.bicep' = if (deployObservability) {
  name: 'deploy-ai-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    baseName: tenant
    environment: environmentName
    location: location
    alertEmail: alertEmail
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output tenant string = tenant
output resourceGroupName string = rgName
output swaHostname string = swa.outputs.defaultHostname
#disable-next-line outputs-should-not-contain-secrets
output swaDeploymentToken string = swa.outputs.deploymentToken
output sqlServerFqdn string = deploySql ? sql!.outputs.serverFqdn : ''
output storageAccountName string = deployStorage ? storage!.outputs.name : ''
output appInsightsConnectionString string = deployObservability ? observability!.outputs.connectionString : ''
