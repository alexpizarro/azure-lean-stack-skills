param serverName string
param databaseName string
param location string
param administratorLogin string

@secure()
param administratorLoginPassword string

param tags object = {}

@description('Serverless (auto-pause, bursty traffic) or Basic (flat ~$5/mo, always-on, steady traffic).')
@allowed(['Serverless', 'Basic'])
param sqlSku string = 'Serverless'

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

// Allow connections from Azure-hosted services (including SWA managed functions)
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'AllowAllAzureIPs'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Serverless tier: auto-pauses after 15 min of inactivity — lowest cost for GENUINELY bursty apps.
// If the DB is small and hit on a steady cadence (health checks, schedulers, polling), serverless
// never pauses and costs MORE than flat Basic (~$5/mo) — see cost-guardrails Guardrail #11.
// Switch with sqlSku = 'Basic' (proven: bc-videohub-lite, ~10x cheaper at its usage).
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: sqlSku == 'Basic' ? {
    name: 'Basic'
    tier: 'Basic'
  } : {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: sqlSku == 'Basic' ? {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2 GB (Basic ceiling)
    requestedBackupStorageRedundancy: 'Local'
  } : {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    autoPauseDelay: 15
    minCapacity: json('0.5')
    maxSizeBytes: 1073741824 // 1 GB
    requestedBackupStorageRedundancy: 'Local'
  }
}

output serverName string = sqlServer.name
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlDatabase.name
