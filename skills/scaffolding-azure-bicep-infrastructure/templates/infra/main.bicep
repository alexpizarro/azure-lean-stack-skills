targetScope = 'subscription'

// ============================================================================
// Modular Azure web-app root — opt-in components via boolean toggles.
// Always provisions: Resource Group + Static Web App.
// Optional: SQL, Storage, Application Insights, Container App.
// ============================================================================

@description('Deployment environment.')
@allowed(['test', 'prod'])
param environmentName string

@description('Azure region for all data resources (RG, SQL, Storage, ACA).')
param location string = 'australiaeast'

// Static Web Apps is a global CDN service — australiaeast isn't a supported
// billing region. Supported: westus2, centralus, eastus2, westeurope, eastasia.
// Hard-coded because changing it has no upside.
var swaLocation = 'eastasia'

// ---------------------------------------------------------------------------
// Naming — formula: {org}-{project}-{component}-{env}
// Set org and project ONCE in infra/environments/{env}.parameters.json
// ---------------------------------------------------------------------------
@description('Short org name used in all Azure resource names (e.g. "acme").')
param org string

@description('Short project name used in all Azure resource names (e.g. "taskapp").')
param project string

var baseName = '${org}-${project}'

var rgName       = '${baseName}-rg-${environmentName}'
var swaName      = '${baseName}-swa-${environmentName}'
var sqlServerName = '${baseName}-sql-${environmentName}'
var sqlDbName    = '${baseName}-sqldb-${environmentName}'

// ---------------------------------------------------------------------------
// Modular toggles — projects opt in to components they actually use
// ---------------------------------------------------------------------------
@description('Deploy SQL Server + Serverless DB.')
param deploySql bool = true

@description('Deploy Storage Account.')
param deployStorage bool = false

@description('Deploy workspace-based Application Insights with daily cap.')
param deployObservability bool = false

// ---------------------------------------------------------------------------
// SQL inputs (only used when deploySql = true)
// ---------------------------------------------------------------------------
@description('SQL Server administrator login name.')
param sqlAdminLogin string = 'sqladmin'

@secure()
@description('SQL Server administrator password. Injected from GitHub Actions secret at deploy time.')
param sqlAdminPassword string = ''

// ---------------------------------------------------------------------------
// Observability inputs (only used when deployObservability = true)
// ---------------------------------------------------------------------------
@description('Owner email for monitoring alerts. Empty = component only, no alert rules.')
param alertEmail string = ''

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------
var tags = {
  environment: environmentName
  project: project
  organization: org
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Resource Group (always)
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
// SQL Server + Serverless Database (optional)
// ---------------------------------------------------------------------------
module sql 'modules/sqlServer.bicep' = if (deploySql) {
  name: 'deploy-sql-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    serverName: sqlServerName
    databaseName: sqlDbName
    location: location
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    tags: tags
  }
}

// Construct connection string inside main.bicep so the password never appears
// as a module output (Bicep linter would flag it; logs could leak it).
var sqlConnectionString = deploySql
  ? 'Server=tcp:${sql!.outputs.serverFqdn},1433;Database=${sqlDbName};User Id=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  : ''

// ---------------------------------------------------------------------------
// Static Web App (always — this is the orchestrator's defining component)
// Per-env SKU: Free in test, Standard in prod (custom domains + SLA).
// ---------------------------------------------------------------------------
module swa 'modules/staticWebApp.bicep' = {
  name: 'deploy-swa-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    name: swaName
    location: swaLocation
    sqlConnectionString: sqlConnectionString
    skuName: environmentName == 'prod' ? 'Standard' : 'Free'
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs (captured by GitHub Actions)
// ---------------------------------------------------------------------------
output resourceGroupName string = rgName
output swaName string = swaName
output swaHostname string = swa.outputs.defaultHostname
// The deployment token is sensitive — the workflow masks it immediately after capture
#disable-next-line outputs-should-not-contain-secrets
output swaDeploymentToken string = swa.outputs.deploymentToken
output sqlServerFqdn string = deploySql ? sql!.outputs.serverFqdn : ''
output sqlDbName string = deploySql ? sqlDbName : ''
