// Shared managed environment for Container Apps and Container Apps Jobs.
// One environment can host many apps/jobs — share to amortise Log Analytics cost.
// Workload profile: Consumption (no idle billing).

param name string
param location string
param tags object = {}

@description('Daily data cap (GB) on the Log Analytics workspace — bounds observability cost.')
param dailyCapGb int = 1

@description('Log retention in days. Workspace minimum 30, maximum 730.')
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${name}-logs'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionInDays
    workspaceCapping: { dailyQuotaGb: dailyCapGb }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

output id string = managedEnv.id
output name string = managedEnv.name
output workspaceId string = workspace.id
output workspaceName string = workspace.name
