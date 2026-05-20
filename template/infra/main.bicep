targetScope = 'subscription'

@description('Deployment environment.')
@allowed(['test', 'prod'])
param environmentName string

@description('Azure region for all resources.')
param location string = 'australiaeast'

@description('SQL Server administrator login name.')
param sqlAdminLogin string = 'sqladmin'

@secure()
@description('SQL Server administrator password. Injected from GitHub Actions secret at deploy time.')
param sqlAdminPassword string

// ---------------------------------------------------------------------------
// Naming — formula: {org}-{project}-{component}-{env}
// Set org and project in infra/environments/{env}.parameters.json
// ---------------------------------------------------------------------------
@description('Short org name used in all Azure resource names (e.g. "acme", "myco"). Set in environments/{env}.parameters.json.')
param org string

@description('Short project name used in all Azure resource names (e.g. "taskapp", "shop"). Set in environments/{env}.parameters.json.')
param project string

var baseName = '${org}-${project}'

var rgName        = '${baseName}-rg-${environmentName}'
var swaName       = '${baseName}-swa-${environmentName}'
var sqlServerName = '${baseName}-sql-${environmentName}'
var sqlDbName     = '${baseName}-sqldb-${environmentName}'

// SWA is a global CDN service — 'australiaeast' is not a supported billing region.
// Supported: westus2, centralus, eastus2, westeurope, eastasia
var swaLocation = 'eastasia'

var tags = {
  environment: environmentName
  project: project
  organization: org
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
// SQL Server + Serverless Database
// ---------------------------------------------------------------------------
module sql 'modules/sqlServer.bicep' = {
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

// Connection string is constructed here and never output — password stays private
var sqlConnectionString = 'Server=tcp:${sql.outputs.serverFqdn},1433;Database=${sqlDbName};User Id=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// ---------------------------------------------------------------------------
// Static Web App (Free tier — includes managed functions)
// ---------------------------------------------------------------------------
module swa 'modules/staticWebApp.bicep' = {
  name: 'deploy-swa-${environmentName}'
  scope: resourceGroup(rgName)
  dependsOn: [rg]
  params: {
    name: swaName
    location: swaLocation
    sqlConnectionString: sqlConnectionString
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
output swaDeploymentToken string = swa.outputs.deploymentToken
output sqlServerFqdn string = sql.outputs.serverFqdn
output sqlDbName string = sqlDbName
