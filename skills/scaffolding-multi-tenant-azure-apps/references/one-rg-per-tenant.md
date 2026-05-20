# One RG per tenant — why

The "one resource group per tenant on a shared subscription" pattern is the default for this skill. Here's why each property matters.

## Why one RG (not one subscription)

| If you choose | You get | You give up |
|---------------|---------|-------------|
| One RG per tenant | Strong resource-level isolation, simple deployment, easy cleanup | Subscription-wide quotas, shared identity |
| One subscription per tenant | Billing isolation, per-tenant quotas, full RBAC isolation | Operational complexity, EA agreement overhead |

For 5–100 tenants, one RG per tenant on a shared subscription is the right trade. You only need separate subscriptions when:
- A regulator (or customer contract) requires it
- You're hitting subscription-wide quotas
- You need per-tenant billing scopes from Azure's invoicing system

## Why one Bicep, many parameter files

| If you choose | You get | You give up |
|---------------|---------|-------------|
| One `main.bicep` + N parameter files | Single source of truth for infra; changes deploy to every tenant uniformly | Some flexibility for tenant-specific architectures |
| One `main.bicep` per tenant | Per-tenant customisation | Drift; hard to maintain |

If a tenant needs a different SKU or extra resource, add it as a conditional `param` with a sensible default, not as a fork.

## Why the `tenant` slug drives names (not the SP)

The tenant slug is the **deploy-time input**, parameter-file-driven. The SP is **CI-time** authentication. They're separate concerns:

- The same SP can deploy multiple tenants (one repo, many environments)
- The tenant slug is reproducible — anyone with the parameter file can deploy
- Resource names stay deterministic regardless of who deploys

If you tied resource names to the SP, you'd have:
- A scaling problem (one SP per tenant)
- A naming churn problem (rotating SPs renames resources)
- A reproducibility problem (deploys from different machines = different names)

## Why default-tenant matches the original single-tenant name

If you ship as single-tenant, then later go multi-tenant, the migration is hard if the default `tenant` param yields different names than the existing resources.

Set the default to match. If your original RG was `acme-taskapp-rg-prod`:

```bicep
param tenant string = 'acme-taskapp'    // default matches existing names
```

Then `{tenant}-rg-prod` = `acme-taskapp-rg-prod` — byte-identical, no migration needed. The first new tenant passes a different slug and gets fresh resources.

## Why storage account name needs an override

Azure storage account names are global, lowercase, alphanumeric, ≤24 chars. The tenant slug might:
- Be too long (`my-very-long-company-name`)
- Already be taken globally (`acmestore` collisions)
- Need a different format for legacy reasons

So the Bicep exposes a `storageAccountName` override:

```bicep
@description('Storage account name override (no hyphens, ≤24 chars). Empty = derive from tenant.')
param storageAccountName string = ''

var derivedName = toLower(replace('${tenant}store${environment}', '-', ''))
var actualName  = empty(storageAccountName) ? derivedName : storageAccountName
```

## Cost reporting per tenant

Tag every resource:

```bicep
var tags = {
  tenant: tenant
  environment: environment
  managedBy: 'bicep'
}
```

Then in Azure Cost Management:
1. Open Cost analysis
2. Group by: Tag → `tenant`
3. Optionally filter by environment

You get per-tenant cost without any extra plumbing.

## Migration: from single-tenant to multi-tenant

If you're already deployed single-tenant and need to add the second customer:

1. Set the default `tenant` param to match your current names (e.g. `acme-taskapp`)
2. Verify your existing deploy is unchanged — `az deployment sub validate` should show no diff
3. Add a new parameter file for the second tenant
4. Deploy it — creates a fully isolated stack
5. Update DNS, customer-facing config, etc.

No data migration needed for the original tenant.
