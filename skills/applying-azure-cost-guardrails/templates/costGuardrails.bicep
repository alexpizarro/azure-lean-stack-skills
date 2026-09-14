// Always-on, Azure-native cost guardrails for one environment's resource group.
// The backstop that needs no human and no repo: it alerts whether or not anyone
// deploys, watches CI, or runs a hook.
//
//   - Action Group        → emails the owner (shared by budget + metric alerts).
//   - Consumption Budget  → monthly $ budget on THIS RG, email at 50/80/100% actual + 100% forecast.
//   - Metric Alerts       → fire if a scale-to-zero Container App never drained to 0 replicas
//                           for a full hour. Budgets lag 8–24h; this is the fast layer.
//
// Deploy OUT-OF-BAND at RG scope, once per environment, from an owner session:
//   az deployment group create -g <rg> --template-file costGuardrails.bicep \
//     --parameters baseName=<org>-<project> environment=<env> ownerEmail=<you> \
//                  budgetAmount=<n> startDate=<YYYY-MM-01> scaleToZeroApps='["<aca-name>"]'
// Why out-of-band: Microsoft.Consumption/budgets needs Cost Management permissions the
// Contributor-only CI SP does not have, and a permission gap must never break a deploy.
//
// Proven: bc-videohub-lite (infra/modules/costGuardrails.bicep) — RG budget + per-resource
// OpenAI budget + stuck-warm alerts on a GPU app and two CPU twins.

@description('Base name, e.g. acme-taskapp.')
param baseName string

@description('Environment: test | prod.')
param environment string

@description('Email that receives cost alerts.')
param ownerEmail string

@description('Monthly cost budget for this RG, in the billing-account currency.')
param budgetAmount int

@description('Budget start — must be the first day of a month, not in the past (YYYY-MM-01).')
param startDate string

@description('Scale-to-zero Container App names in this RG. Each gets a "never drained to 0 replicas for 1h" alert. Empty = no replica alerts.')
param scaleToZeroApps array = []

@description('Optional: full resource id of a single high-risk resource (e.g. an Azure OpenAI account) that gets its OWN monthly cap. Empty = none.')
param perResourceBudgetId string = ''

@description('Monthly cap for the per-resource budget (only used when perResourceBudgetId is set).')
param perResourceBudgetAmount int = 10

var agShort = 'cost${environment}'

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${baseName}-cost-alerts-${environment}'
  location: 'Global'
  properties: {
    groupShortName: substring(agShort, 0, min(length(agShort), 12))
    enabled: true
    emailReceivers: [
      {
        name: 'owner'
        emailAddress: ownerEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

var notifications = {
  Actual_50: {
    enabled: true
    operator: 'GreaterThanOrEqualTo'
    threshold: 50
    thresholdType: 'Actual'
    contactEmails: [ownerEmail]
    contactGroups: [actionGroup.id]
  }
  Actual_80: {
    enabled: true
    operator: 'GreaterThanOrEqualTo'
    threshold: 80
    thresholdType: 'Actual'
    contactEmails: [ownerEmail]
    contactGroups: [actionGroup.id]
  }
  Actual_100: {
    enabled: true
    operator: 'GreaterThanOrEqualTo'
    threshold: 100
    thresholdType: 'Actual'
    contactEmails: [ownerEmail]
    contactGroups: [actionGroup.id]
  }
  Forecast_100: {
    enabled: true
    operator: 'GreaterThanOrEqualTo'
    threshold: 100
    thresholdType: 'Forecasted'
    contactEmails: [ownerEmail]
    contactGroups: [actionGroup.id]
  }
}

// Monthly budget on the whole resource group.
resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: '${baseName}-rg-monthly-${environment}'
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: notifications
  }
}

// Optional second budget filtered by DIMENSION to one resource id, so a runaway
// feature (AI, media processing) trips its own cap before the RG budget moves.
resource perResourceBudget 'Microsoft.Consumption/budgets@2024-08-01' = if (!empty(perResourceBudgetId)) {
  name: '${baseName}-resource-monthly-${environment}'
  properties: {
    category: 'Cost'
    amount: perResourceBudgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    filter: {
      dimensions: {
        name: 'ResourceId'
        operator: 'In'
        values: [
          perResourceBudgetId
        ]
      }
    }
    notifications: notifications
  }
}

// Stuck-warm tripwire: a scale-to-zero app whose Replicas MINIMUM stayed > 0 for a
// full hour is being held awake (gotchas #41–#43). Fires long before the budget does.
resource stuckWarm 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for appName in scaleToZeroApps: {
    name: '${appName}-stuck-warm'
    location: 'global'
    properties: {
      description: '${appName} has not scaled to zero for 1h — possible cost leak (cost-guardrails Guardrail #12).'
      severity: 2
      enabled: true
      scopes: [
        resourceId('Microsoft.App/containerApps', appName)
      ]
      evaluationFrequency: 'PT15M'
      windowSize: 'PT1H'
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [
          {
            name: 'replicaNeverZero'
            metricNamespace: 'microsoft.app/containerapps'
            metricName: 'Replicas'
            operator: 'GreaterThan'
            threshold: 0
            timeAggregation: 'Minimum'
            criterionType: 'StaticThresholdCriterion'
          }
        ]
      }
      autoMitigate: true
      actions: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
]

output actionGroupId string = actionGroup.id
