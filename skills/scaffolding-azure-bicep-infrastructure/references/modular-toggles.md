# Modular toggle pattern

`main.bicep` exposes a boolean parameter for each optional component. Projects opt in to what they need.

## Why

The original starter unconditionally provisioned SWA + SQL. Projects that didn't need SQL (or needed *only* Storage + ACA) had to fork the Bicep. The modular toggle pattern lets one `main.bicep` serve every project shape.

## Pattern

```bicep
targetScope = 'subscription'

@allowed(['test', 'prod'])
param environment string

param location string = 'australiaeast'

// Required components
param org string
param project string

// Optional components — projects opt in
param deploySql bool = true
param deployStorage bool = false
param deployObservability bool = false
param deployContainerApp bool = false

// SQL password only required when SQL is enabled
@secure()
param sqlAdminPassword string = ''

var baseName = '${org}-${project}'
var rgName   = '${baseName}-rg-${environment}'

module rg 'modules/resourceGroup.bicep' = {
  name: 'deploy-rg-${environment}'
  params: { name: rgName, location: location }
}

// SWA is always deployed (the orchestrator's defining component)
module swa 'modules/staticWebApp.bicep' = {
  name: 'deploy-swa-${environment}'
  scope: resourceGroup(rgName)
  params: { ... }
  dependsOn: [rg]
}

// Everything else is conditional
module sql 'modules/sqlServer.bicep' = if (deploySql) {
  name: 'deploy-sql-${environment}'
  scope: resourceGroup(rgName)
  params: { ... }
  dependsOn: [rg]
}

module storage 'modules/storageAccount.bicep' = if (deployStorage) {
  name: 'deploy-storage-${environment}'
  scope: resourceGroup(rgName)
  params: { ... }
  dependsOn: [rg]
}

module observability 'modules/applicationInsights.bicep' = if (deployObservability) {
  name: 'deploy-ai-${environment}'
  scope: resourceGroup(rgName)
  params: { ... }
  dependsOn: [rg]
}
```

## Conditional outputs

When an output depends on an optional module, use a ternary + the `!` non-null assertion:

```bicep
output appInsightsConnectionString string = deployObservability ? observability!.outputs.connectionString : ''
output storageEndpoint string             = deployStorage      ? storage!.outputs.primaryEndpoint        : ''
output sqlServerFqdn string               = deploySql         ? sql!.outputs.serverFqdn                  : ''
```

The workflow can check `if [ -n "$STORAGE_ENDPOINT" ]` before using the value.

## Parameter file shape

Test environment with SQL only:

```json
{
  "parameters": {
    "environment": { "value": "test" },
    "org":         { "value": "acme" },
    "project":     { "value": "taskapp" },
    "deploySql":         { "value": true  },
    "deployStorage":     { "value": false },
    "deployObservability": { "value": false }
  }
}
```

Prod environment with full stack:

```json
{
  "parameters": {
    "environment": { "value": "prod" },
    "org":         { "value": "acme" },
    "project":     { "value": "taskapp" },
    "deploySql":         { "value": true },
    "deployStorage":     { "value": true },
    "deployObservability": { "value": true },
    "alertEmail":        { "value": "ops@acme.com" }
  }
}
```

## Adding a new optional component

1. Create the module under `infra/modules/`.
2. Add a `deployX bool = false` param to `main.bicep`.
3. Add the `module x ... = if (deployX) { ... }` block.
4. Add any conditional outputs.
5. Set `deployX: { "value": true }` in the parameter file(s) where the project wants it.
6. If the workflow needs to do something with the output, gate it with `if [ -n "$X" ]`.

## Anti-pattern

Don't use `if` to switch *between* implementations:

```bicep
// BAD — duplicates logic, hard to maintain
module sqlServerless 'modules/sqlServerless.bicep' = if (useServerless) { ... }
module sqlProvisioned 'modules/sqlProvisioned.bicep' = if (!useServerless) { ... }
```

Instead, pass the variant as a param into a single module:

```bicep
// GOOD
module sql 'modules/sqlServer.bicep' = if (deploySql) {
  params: { sku: useServerless ? 'GP_S_Gen5_1' : 'GP_Gen5_2' }
}
```
