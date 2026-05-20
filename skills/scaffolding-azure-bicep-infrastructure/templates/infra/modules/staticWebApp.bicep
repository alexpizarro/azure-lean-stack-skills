param name string
param location string
param tags object = {}

@description('Per-env SKU. Free = test default; Standard = prod (custom domains + SLA + larger function quota).')
param skuName string = 'Free'

@secure()
@description('SQL connection string passed in by main.bicep. Empty string is acceptable — the app setting just won\'t be set.')
param sqlConnectionString string = ''

resource swa 'Microsoft.Web/staticSites@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    buildProperties: {
      skipGithubActionWorkflowGeneration: true
    }
  }
}

// App settings are available as environment variables in managed functions.
// SQL_CONNECTION_STRING is only set when sqlConnectionString is non-empty.
resource swaAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = if (!empty(sqlConnectionString)) {
  parent: swa
  name: 'appsettings'
  properties: {
    SQL_CONNECTION_STRING: sqlConnectionString
  }
}

output id string = swa.id
output name string = swa.name
output defaultHostname string = swa.properties.defaultHostname
// Deployment token used by GitHub Actions — the workflow masks it immediately with ::add-mask::
#disable-next-line outputs-should-not-contain-secrets
output deploymentToken string = swa.listSecrets().properties.apiKey
