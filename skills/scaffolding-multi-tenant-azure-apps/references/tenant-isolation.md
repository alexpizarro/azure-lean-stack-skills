# Tenant isolation — trade-offs

Three patterns for "multi-tenant" on Azure. This skill implements **#2 (one RG per tenant on shared subscription)** as the default because it has the best cost-vs-isolation trade-off for small-to-mid scale.

## 1. Row-level multi-tenancy (shared infra)

| | |
|---|---|
| **Isolation** | Logical — tenants share databases, storage accounts, ACA |
| **Cost** | Lowest |
| **Risk** | Cross-tenant data leak if app code has a bug |
| **Use when** | SaaS with thousands of small tenants, low isolation requirements |

Not implemented by this skill — it's a different shape entirely.

## 2. One RG per tenant on a shared subscription (this skill)

| | |
|---|---|
| **Isolation** | Strong — each tenant has its own SQL, Storage, SWA |
| **Cost** | Per-tenant infrastructure cost; benefits from consumption tiers (most tiers $0 when idle) |
| **Risk** | Subscription-wide limits (quotas) shared across tenants |
| **Use when** | ~5–100 tenants, B2B with compliance asks, predictable per-tenant cost |

The pattern this skill ships.

## 3. One subscription per tenant

| | |
|---|---|
| **Isolation** | Strongest — billing, quotas, RBAC all per-tenant |
| **Cost** | Higher overhead (Azure billing scopes, EA agreement, support) |
| **Risk** | Operational complexity scales linearly with tenant count |
| **Use when** | Compliance-driven (e.g. HIPAA, FedRAMP), enterprise customers paying for it |

Use Azure Management Groups + AzOps / Terraform for this. Out of scope here.

## What each tenant gets in pattern #2

Each tenant deployment creates:
- One Resource Group
- One Static Web App (or Container App)
- One SQL Server + Database (if `deploySql`)
- One Storage Account (if `deployStorage`)
- One App Insights + Log Analytics workspace (if `deployObservability`)

The shared subscription has:
- One ACR (if using private images) — referenced by every tenant
- One Entra tenant with all customer users
- One billing account

## What's shared across tenants

Resources that don't benefit from per-tenant isolation:

- **Image registry** — same Docker image deployed to every tenant
- **DNS zone** — `*.example.com` resolves to tenant-specific subdomains
- **Customer identity** — one Entra tenant with multi-tenant app registrations
- **Monitoring aggregation** — optional shared Log Analytics workspace for cross-tenant alerts (often paired with per-tenant ones)

## Limits to watch

Subscription-wide limits that can become tight at 50+ tenants:

| Resource | Default limit | When to ask for increase |
|----------|---------------|-------------------------|
| Resource Groups per subscription | 980 | At ~500 tenants |
| Storage accounts per subscription | 250 | At ~150 tenants |
| vCPU quota (per region, per family) | varies | Check before scale-up |
| Managed identities per subscription | 4000 | Rarely hit |

When you hit a limit, request a quota increase via Azure Portal or split into multiple subscriptions.

## Tenant lifecycle

Onboarding:
1. New tenant slug agreed
2. Copy a parameter file (`infra/environments/{tenant}.parameters.json`)
3. Add a GitHub Environment named after the tenant
4. Set environment-scoped secrets
5. Deploy via workflow_dispatch

Offboarding:
1. Soft-delete: rename RG with `archived-` prefix, scale ACA to 0, freeze SWA. Keep data for retention period.
2. Hard-delete: `az group delete --name {tenant}-rg-{env} --yes`. Verify the GitHub Environment is also deleted.

Audit each tenant's resources:

```bash
az resource list --tag tenant="$TENANT_SLUG" -o table
```
