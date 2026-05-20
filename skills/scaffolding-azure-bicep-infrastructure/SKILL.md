---
name: scaffolding-azure-bicep-infrastructure
description: Generates a subscription-scoped Bicep stack + GitHub Actions workflows for an Azure web app, with opt-in module toggles (SQL, Storage, Observability) and the {org}-{project}-{component}-{env} naming formula. Use when bootstrapping a new Azure project's IaC, adding a Bicep module, or refactoring into the modular-toggle pattern.
---

# Scaffolding Azure Bicep Infrastructure

Generates the Bicep + workflow files for a new Azure web app. Modular by default: every component (SQL, Storage, Observability) is an opt-in boolean toggle on `main.bicep`, so projects only provision what they actually use.

## When to invoke

- New project: generate `infra/`, `infra/environments/`, `.github/workflows/`
- Existing project: add a new module or refactor into the modular-toggle pattern

## Workflow checklist

Copy this checklist into your response and check items off as you complete them:

```
Azure Bicep scaffolding:
- [ ] Step 1: Collect inputs (org, project, GitHub repo, components)
- [ ] Step 2: Generate infra/main.bicep with modular toggles
- [ ] Step 3: Generate infra/modules/ (resourceGroup, staticWebApp, sqlServer; add storage/observability/aca if toggled)
- [ ] Step 4: Generate infra/environments/test.parameters.json + prod.parameters.json
- [ ] Step 5: Generate .github/workflows/ (deploy-test.yml, deploy-prod.yml, pr-checks.yml)
- [ ] Step 6: Generate infra/sql/migrations/000_migration_history.sql + 001_create_items_table.sql
- [ ] Step 7: Verify naming consistency — every resource uses {org}-{project}-{component}-{env}
- [ ] Step 8: Run cost-guardrails audit before first deploy (skill: applying-azure-cost-guardrails)
```

## Before starting, collect

1. **org** — short org/company prefix (e.g. `acme`)
2. **project** — short app name (e.g. `taskapp`)
3. **GitHub repo** — `owner/repo-name`
4. **Components needed** — SQL? Storage? Observability? FC1? Container Apps?

## Files to generate

For a basic SWA + SQL project:

```
infra/
├── main.bicep
├── environments/
│   ├── test.parameters.json
│   └── prod.parameters.json
├── modules/
│   ├── resourceGroup.bicep
│   ├── staticWebApp.bicep
│   └── sqlServer.bicep
└── sql/migrations/
    ├── 000_migration_history.sql
    └── 001_create_items_table.sql
.github/workflows/
├── deploy-test.yml
└── deploy-prod.yml
```

Add modules only when their toggle is true.

## The modular toggle pattern

`main.bicep` exposes boolean params for each optional component. Every project provisions the resource group + SWA; everything else is opt-in:

```bicep
@allowed(['test', 'prod'])
param environment string

param deploySql bool = true
param deployStorage bool = false
param deployObservability bool = false
param deployContainerApp bool = false

module sqlServer 'modules/sqlServer.bicep' = if (deploySql) { ... }
module storage 'modules/storageAccount.bicep' = if (deployStorage) { ... }
module ai 'modules/applicationInsights.bicep' = if (deployObservability) { ... }
```

Outputs that depend on optional modules use the `!` non-null assertion guarded by the boolean:

```bicep
output appInsightsConnectionString string = deployObservability ? ai!.outputs.connectionString : ''
```

See [references/modular-toggles.md](references/modular-toggles.md) for the complete pattern.

## Naming formula

`{org}-{project}-{component}-{env}` — see [references/naming-formula.md](references/naming-formula.md).

Set `org` and `project` once in `infra/environments/{env}.parameters.json` and every resource name cascades.

## Per-environment SKU selection

Test environments run on free / smallest tiers; prod gets the paid SKU only where needed:

```bicep
module swa 'modules/staticWebApp.bicep' = {
  params: {
    skuName: environment == 'prod' ? 'Standard' : 'Free'
  }
}
```

See [references/per-env-sku.md](references/per-env-sku.md).

## Critical rules

- **`main.bicep` is `targetScope = 'subscription'`** — needed so it can create the RG.
- **Modules are RG-scoped** — `scope: resourceGroup(rgName)` + `dependsOn: [rg]`.
- **`.parameters.json` not `.bicepparam`** — the workflow injects the SQL password via `--parameters sqlAdminPassword=...` which `.bicepparam` doesn't support.
- **SWA location is `eastasia`**, hard-coded as `var swaLocation = 'eastasia'`. Everything else uses `location` param (defaults `australiaeast`).
- **SQL connection string never output** — construct it inside `main.bicep`, pass to SWA module as `@secure()` param.
- **Bicep self-reference for app URLs** — use `'https://${swa.properties.defaultHostname}'` for `APP_BASE_URL`; no parameter needed.

## Workflow templates

The workflow files in [templates/.github/workflows/](templates/.github/workflows/) include:

- OIDC login via `azure/login@v2`
- **Conditional Bicep**: `git diff` checks `infra/` paths, skips Bicep + migrations on code-only pushes (saves 3–5 min/run)
- **SWA token fallback**: when Bicep is skipped, fetches the SWA deployment token via `az staticwebapp secrets list`
- SQL password masked with `::add-mask::`

See the deployment workflow files in `templates/.github/workflows/` for the complete pattern.

## Composes with

- [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md) — for the SP + GitHub secrets that the workflow uses
- [managing-azure-sql-migrations](../managing-azure-sql-migrations/SKILL.md) — for the SQL section of the workflow
- [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md) — for the SWA-specific module + app config
- [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md) — when `deployStorage = true`, prefer the storage module from there
- [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md) — when `deployObservability = true`
- [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) — to verify SKUs before deploy

## Templates included

| File | Purpose |
|------|---------|
| [templates/infra/main.bicep](templates/infra/main.bicep) | Subscription-scoped root with modular toggles |
| [templates/infra/modules/resourceGroup.bicep](templates/infra/modules/resourceGroup.bicep) | RG creation |
| [templates/infra/modules/staticWebApp.bicep](templates/infra/modules/staticWebApp.bicep) | SWA with per-env SKU |
| [templates/infra/modules/sqlServer.bicep](templates/infra/modules/sqlServer.bicep) | SQL Server + Serverless DB |
| [templates/infra/environments/test.parameters.json](templates/infra/environments/test.parameters.json) | Test env params |
| [templates/infra/environments/prod.parameters.json](templates/infra/environments/prod.parameters.json) | Prod env params |
| [templates/.github/workflows/deploy-test.yml](templates/.github/workflows/deploy-test.yml) | Test deploy workflow |
| [templates/.github/workflows/deploy-prod.yml](templates/.github/workflows/deploy-prod.yml) | Prod deploy workflow |
