param name string
param location string
param tags object = {}

@secure()
param sqlConnectionString string

resource swa 'Microsoft.Web/staticSites@2023-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    buildProperties: {
      skipGithubActionWorkflowGeneration: true
    }
  }
}

// App settings are available as environment variables in managed functions
resource swaAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
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
