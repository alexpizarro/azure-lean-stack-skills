---
name: scaffolding-multi-tenant-azure-apps
description: Scaffolds a multi-tenant Azure app where each tenant gets its own resource group on a shared subscription, with one Bicep main.bicep driven by a single tenant parameter that cascades through every resource name. The default tenant keeps the original (single-tenant) names byte-identical so the pattern works for the first deployment with no migration. Use when onboarding the second tenant onto an app that started single-tenant, designing a multi-school/multi-clinic/multi-org SaaS, or refactoring shared resources to be per-tenant.
---

# Scaffolding Multi-Tenant Azure Apps

Multi-tenant pattern with **one resource group per tenant on a shared subscription**. One `tenant` parameter drives the RG and every resource name. Adding a tenant = redeploy with a new param value.

## When to use this pattern

| Need | This skill |
|------|-----------|
| One product, multiple isolated customers (schools, clinics, agencies) | Yes |
| Per-tenant DB, per-tenant storage, per-tenant ACA | Yes |
| Multi-tenant SaaS where customers share a single DB | No — that's row-level multi-tenancy, not infra-level |
| Different products for different customers | No — use per-product subscriptions instead |

## Workflow checklist

Copy this checklist and tick items off:

```
Onboarding a new tenant:
- [ ] Step 1: Agree on the tenant slug (kebab-case, ≤20 chars, no Azure reserved words)
- [ ] Step 2: Verify the derived storage account name fits (≤24 chars, alphanumeric) — provide override if not
- [ ] Step 3: Copy infra/environments/prod.parameters.json → infra/environments/{tenant}.parameters.json
- [ ] Step 4: Edit tenant slug + storageAccountName override if needed
- [ ] Step 5: Create a new branch for this tenant if using branch-per-tenant (recommended for full isolation)
- [ ] Step 6: Add OIDC SP + federated credential bound to the new branch (skill: configuring-azure-oidc-for-github-actions)
- [ ] Step 7: Generate per-tenant SQL password + add as GitHub secret
- [ ] Step 8: Push to the tenant branch → workflow provisions the isolated stack
- [ ] Step 9: Verify per-tenant cost reporting: `az resource list --tag tenant=$SLUG -o table`
```

## The core idea

`main.bicep` accepts a `tenant` param. Default value matches your original (single-tenant) naming so the first deployment doesn't need to migrate anything:

```bicep
@description('Tenant slug — drives all resource names + the RG.')
param tenant string = 'acme-default'

// Storage account name can\'t have hyphens, ≤24 chars. Provide an override
// for tenants whose slug doesn\'t yield a valid storage name.
@description('Storage account name override (no hyphens, ≤24 chars). Empty = derive from tenant.')
param storageAccountName string = ''

module rg 'modules/resourceGroup.bicep' = {
  name: 'deploy-rg-${environment}'
  params: { name: '${tenant}-rg-${environment}' }
}

module storage 'modules/storage.bicep' = {
  scope: resourceGroup('${tenant}-rg-${environment}')
  params: {
    name: empty(storageAccountName) ? toLower(replace('${tenant}store', '-', '')) : storageAccountName
  }
}

// ... every other module follows the same pattern
```

See [references/tenant-isolation.md](references/tenant-isolation.md) for the trade-offs and [references/one-rg-per-tenant.md](references/one-rg-per-tenant.md) for the why.

## Adding a new tenant

```bash
# 1. Copy the parameter file
cp infra/environments/prod.parameters.json infra/environments/acme-corp.parameters.json

# 2. Edit the new file — set tenant slug + storage override if needed
{
  "parameters": {
    "environmentName": { "value": "prod" },
    "tenant":          { "value": "acme-corp" },
    "storageAccountName": { "value": "acmecorpstoreprod" }
  }
}

# 3. Deploy
az deployment sub create \
  --location australiaeast \
  --template-file infra/main.bicep \
  --parameters @infra/environments/acme-corp.parameters.json \
  --parameters sqlAdminPassword="$NEW_PASSWORD"
```

The deploy creates a fully isolated stack: new RG, new SQL, new Storage, new SWA, new ACA — same code paths, separate resources.

## Per-tenant naming

| Resource | Name |
|----------|------|
| Resource Group | `{tenant}-rg-{env}` |
| Static Web App | `{tenant}-swa-{env}` |
| SQL Server | `{tenant}-sql-{env}` |
| SQL Database | `{tenant}-db-{env}` |
| Storage account | `{tenant}store{env}` (no hyphens, ≤24 chars) |
| Container App | `{tenant}-aca-{env}` |
| App Insights | `{tenant}-ai-{env}` |

The `org` + `project` formula becomes a `tenant` formula. If you already shipped single-tenant with `{org}-{project}-*` names, set `tenant = '{org}-{project}'` as the default — the names stay byte-identical.

## Per-tenant secrets

GitHub secrets are per-repo, not per-tenant. Two options:

1. **One repo per tenant** — heavy, but each tenant gets its own SP, secrets, deployment pipeline. Best for fully separate compliance domains.
2. **One repo, environment-scoped secrets** — use [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments) named after the tenant. Each environment has its own `SQL_ADMIN_PASSWORD`, `AZURE_CLIENT_ID`, etc. Best for ~5–20 tenants.

The federated credential subject changes to:

```
repo:{owner}/{repo}:environment:acme-corp-prod
```

## Per-tenant cost tracking

Tag every resource with the tenant slug. Azure Cost Management can then group by tag:

```bicep
var tags = {
  tenant: tenant
  environment: environment
  managedBy: 'bicep'
}
```

Then in Cost Management:
```
Group by: Tag: tenant
```

Per-tenant invoices/chargebacks become trivial.

## When to break this pattern

- **Shared resources by design** — e.g. one ACR shared across all tenants for pulling the same image. Declare those in a separate `infra/shared/main.bicep` deployed once per region; refer to them by resource ID in tenant deployments.
- **Tenant-specific overrides** — sometimes a customer needs a different SKU. Add a tenant-scoped param file and override.

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — the underlying modular Bicep
- [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) — for per-tenant cost reporting
- [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md) — for environment-scoped OIDC

## Templates

| File | Purpose |
|------|---------|
| [templates/multi-tenant-main.bicep](templates/multi-tenant-main.bicep) | main.bicep with the tenant param pattern |
