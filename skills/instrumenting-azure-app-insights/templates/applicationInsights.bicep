// Workspace-based Application Insights with dailyQuotaGb cost cap.
// Optional metric alerts when alertEmail is non-empty.
//
// Outputs the connection string — the workflow sets it as the
// APPLICATIONINSIGHTS_CONNECTION_STRING app setting on SWA / Container App / FC1.

@description('Base name (e.g. acme-taskapp).')
param baseName string

@description('Environment: test | prod.')
param environment string

@description('Azure region.')
param location string

@description('Owner email for monitoring alerts. Empty = component only, no alerts.')
param alertEmail string = ''

@description('Daily ingestion cap (GB). Hard guardrail against runaway logging cost.')
param dailyCapGb int = 1

@description('Log retention in days. 30 is included in ingestion price.')
param retentionInDays int = 30

@description('5xx alert threshold — fires when failed requests exceed this in a 15-min window.')
param failedRequestThreshold int = 5

@description('Exception alert threshold — fires when server exceptions exceed this in a 15-min window.')
param exceptionThreshold int = 5

param tags object = {}

var workspaceName  = '${baseName}-logs-${environment}'
var componentName  = '${baseName}-ai-${environment}'
var actionGroupName = '${baseName}-alerts-${environment}'
var createAlerts = !empty(alertEmail)

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
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

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: componentName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Action Group — single email receiver. Extend with SMS / webhook as needed.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (createAlerts) {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: substring('${baseName}alert', 0, 12)
    enabled: true
    emailReceivers: [
      {
        name: 'owner'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// 5xx / failed-request spike
resource failedRequestsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (createAlerts) {
  name: '${baseName}-5xx-${environment}'
  location: 'global'
  tags: tags
  properties: {
    severity: 1
    enabled: true
    scopes: [appInsights.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'failedRequests'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: failedRequestThreshold
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [{ actionGroupId: actionGroup.id }]
  }
}

// Server exception spike (catches SQL failures, auth failures surfaced as exceptions)
resource exceptionsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (createAlerts) {
  name: '${baseName}-exceptions-${environment}'
  location: 'global'
  tags: tags
  properties: {
    severity: 1
    enabled: true
    scopes: [appInsights.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'exceptions'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'exceptions/server'
          operator: 'GreaterThan'
          threshold: exceptionThreshold
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [{ actionGroupId: actionGroup.id }]
  }
}

#disable-next-line outputs-should-not-contain-secrets
output connectionString string = appInsights.properties.ConnectionString
output appInsightsName string = appInsights.name
output workspaceName string = workspace.name
output workspaceId string = workspace.id
