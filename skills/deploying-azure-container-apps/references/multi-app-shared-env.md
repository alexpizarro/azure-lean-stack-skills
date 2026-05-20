# One managed environment, many apps

A `Microsoft.App/managedEnvironments` resource owns: VNet (optional), Log Analytics workspace integration, and the workload profile. **One env can host many Container Apps and Jobs.**

## Why share

- **Cost:** One Log Analytics workspace shared across apps. Daily cap applies once, not N times.
- **Networking:** If you ever attach a VNet, all apps inherit it automatically.
- **Observability:** All logs land in the same Log Analytics — easier cross-app queries.
- **Simplicity:** Fewer resources to manage.

## When NOT to share

- Hard isolation requirement (different VNets, different log retention, different ownership)
- Different regions (env is regional)

## Pattern in Bicep

```bicep
// One env, created once
module env 'modules/managedEnv.bicep' = {
  name: 'deploy-aca-env-${environment}'
  scope: resourceGroup(rgName)
  params: {
    name: '${baseName}-aca-env-${environment}'
    location: location
  }
  dependsOn: [rg]
}

// Multiple apps reuse it
module apiApp 'modules/containerApp.bicep' = {
  params: {
    name: '${baseName}-api-${environment}'
    managedEnvironmentId: env.outputs.id
    image: '$ACR/api:latest'
    targetPort: 8000
    ...
  }
}

module workerApp 'modules/containerApp.bicep' = {
  params: {
    name: '${baseName}-worker-${environment}'
    managedEnvironmentId: env.outputs.id
    image: '$ACR/worker:latest'
    targetPort: 0                 // no ingress — internal worker
    ...
  }
}

module syncJob 'modules/containerAppJob.bicep' = {
  params: {
    name: '${baseName}-sync-${environment}'
    environmentId: env.outputs.id
    image: '$ACR/sync:latest'
    triggerType: 'Schedule'
    cronExpression: '0 2 * * *'
  }
}
```

## Workload profile on the env

Always declare a Consumption profile so child apps/jobs can opt into scale-to-zero:

```bicep
resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
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
```

Each child app/job then sets `workloadProfileName: 'Consumption'`.

## Log Analytics workspace bounds the cost

Attach a workspace with a daily cap so a runaway log volume can't blow up the bill:

```bicep
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: 1 }       // ← the actual cost guardrail
  }
}
```

See [instrumenting-azure-app-insights](../../instrumenting-azure-app-insights/SKILL.md) for the full observability setup.

## Naming convention

| Resource | Name |
|----------|------|
| Managed environment | `{org}-{project}-aca-env-{env}` |
| Log Analytics workspace | `{org}-{project}-logs-{env}` |
| Container App | `{org}-{project}-{role}-{env}` (`api`, `worker`, `web`) |
| Container Apps Job | `{org}-{project}-{role}-job-{env}` |
