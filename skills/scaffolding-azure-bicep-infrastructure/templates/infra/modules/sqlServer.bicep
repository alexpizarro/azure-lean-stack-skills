param serverName string
param databaseName string
param location string
param administratorLogin string

@secure()
param administratorLoginPassword string

param tags object = {}

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
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
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIPs'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Serverless tier: auto-pauses after 15 min of inactivity — lowest cost for low-volume apps
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
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
