# Per-environment SKU selection

Test environments stay on free / smallest tiers to keep costs near zero. Prod gets the paid SKU only where it materially helps (custom domains, SLA, performance).

## Pattern

Pass `environment` into modules; let each module pick its SKU:

```bicep
module swa 'modules/staticWebApp.bicep' = {
  params: {
    name: '${baseName}-swa-${environment}'
    location: swaLocation
    skuName: environment == 'prod' ? 'Standard' : 'Free'
  }
}
```

Inside the module:

```bicep
param skuName string = 'Free'

resource swa 'Microsoft.Web/staticSites@2023-01-01' = {
  ...
  sku: {
    name: skuName
    tier: skuName
  }
}
```

## Recommended per-env defaults

| Service | Test SKU | Prod SKU | Notes |
|---------|----------|----------|-------|
| Static Web App | `Free` | `Standard` | Standard adds custom domains, SLA, larger function quota |
| SQL Database | `GP_S_Gen5_1` (Serverless) | `GP_S_Gen5_1` (Serverless) | Same — auto-pause handles cost in both |
| Storage Account | `Standard_LRS` | `Standard_LRS` or `Standard_GRS` | LRS for non-critical; GRS for backups |
| Log Analytics | `PerGB2018` + `dailyQuotaGb: 1` | `PerGB2018` + `dailyQuotaGb: 5` | Daily cap is the actual cost control |
| Container App (min replicas) | `0` | `0` (or `1` if cold start matters) | Scale-to-zero is the default cost win |
| Function App | `Y1` (Consumption) or `FC1` | same | No fixed-cost plan |

## Per-env CORS / hostnames

Same shape — keep the parameter on `main.bicep`, branch on `environment`:

```bicep
module storage 'modules/storageAccount.bicep' = if (deployStorage) {
  params: {
    corsAllowedOrigins: environment == 'prod'
      ? ['https://app.example.com']
      : ['https://test.example.com', 'http://localhost:5173']
  }
}
```

## Anti-pattern

Don't put environment-specific values in the parameter file when they can be derived from `environment`:

```json
// BAD — drift risk: prod params and test params can diverge silently
"swaSkuName": { "value": "Free" }
```

Instead, derive from the `environment` param in Bicep. Parameter files stay almost identical between environments, and a single grep finds every per-env behaviour.

## When to deviate

Override the default by exposing the SKU as a Bicep param and setting it explicitly in the parameter file. Use this when:

- A test environment needs to validate a paid-tier feature
- A prod environment needs to be cost-constrained (early-stage product)
- Multiple prod environments exist with different cost profiles

In those cases, document *why* the override exists at the top of the parameter file.
