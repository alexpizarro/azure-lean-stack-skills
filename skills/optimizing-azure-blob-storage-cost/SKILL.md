---
name: optimizing-azure-blob-storage-cost
description: Configures Azure Blob Storage with lifecycle rules that auto-delete stale temp blobs and tier production data through Hot → Cool → Cold without rehydration latency. Provides CORS rules tuned for SPA + SAS uploads/Range reads, public-read branding container alongside private app containers, and SKU/redundancy guidance to keep cost minimal. Use when adding blob storage for uploads, designing storage for a media-heavy app, or auditing an existing storage account for cost waste.
---

# Optimizing Azure Blob Storage Cost

Default-low-cost blob storage with lifecycle rules tuned for media workloads (and any pattern with ephemeral temp blobs + long-lived primary blobs).

## When to invoke

- Adding a blob storage account to a project
- Designing for uploads (SAS-based) + serving (Range / CORS)
- Auditing an existing storage account that's growing unbounded
- A project that stores media (video, large images, archives) where retention > 60 days

## The two-pattern playbook

### Pattern A: temp + permanent containers

Most apps have two flavours of blob:
- **Temp** — short-lived working data (uploads being processed, intermediate transformations, cache)
- **Permanent** — user-visible content (videos, images, exports)

Apply different lifecycle rules to each:

```bicep
resource tempBlobLifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        // Rule 1: delete stale temp blobs after 7 days
        {
          enabled: true
          name: 'delete-stale-temp-blobs'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['incoming/', 'processor-jobs/', 'tmp/']
            }
            actions: {
              baseBlob: { delete: { daysAfterModificationGreaterThan: 7 } }
            }
          }
        }
        // Rule 2: age permanent blobs through tiers — NEVER use Archive for
        // playable/viewable content (rehydration takes hours)
        {
          enabled: true
          name: 'tier-aging-content'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['videos/', 'images/', 'exports/']
            }
            actions: {
              baseBlob: {
                tierToCool: { daysAfterModificationGreaterThan: 60 }
                tierToCold: { daysAfterModificationGreaterThan: 180 }
                // intentionally NO tierToArchive — needs rehydration
              }
            }
          }
        }
      ]
    }
  }
}
```

See [references/lifecycle-rules.md](references/lifecycle-rules.md).

### Pattern B: per-container public/private

Most containers stay private (`publicAccess: 'None'`) with SAS-based access. One opt-in public-read container for assets that need to be served via plain URLs (branding, public catalog images):

```bicep
resource brandingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'branding'
  properties: { publicAccess: 'Blob' }    // read-only public access
}
```

To allow this, the storage account itself must set `allowBlobPublicAccess: true`. Other containers remain `publicAccess: 'None'` — that's the explicit per-container setting.

## Storage account defaults

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }            // LRS = cheapest. Use GRS only when DR matters.
  properties: {
    accessTier: 'Hot'                      // Hot for new blobs (lifecycle ages them later)
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true            // gated per-container; flip to false if no public container exists
  }
}
```

| Setting | Default | When to change |
|---------|---------|---------------|
| `sku.name` | `Standard_LRS` | `Standard_GRS` for geo-redundant backups (~2× cost) |
| `accessTier` | `Hot` | Set `Cool` at account level if 95%+ of writes are write-once-read-rarely |
| `allowBlobPublicAccess` | `true` only if a public container exists | `false` otherwise — defence in depth |

See [references/access-tiers.md](references/access-tiers.md).

## CORS for SPA + SAS

Browser uploads via SAS and Range reads (e.g. video players with `crossOrigin="anonymous"`) need CORS:

```bicep
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            'https://app.example.com'
            'http://localhost:5173'
          ]
          allowedMethods: ['GET', 'PUT', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']                    // required for Range responses
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}
```

See [references/cors-for-spa.md](references/cors-for-spa.md).

## The Archive trap

**Do not** use `tierToArchive` in lifecycle rules for content that needs to stay playable. Archive tier requires manual **rehydration** that takes 1–15 hours and bills extra. Symptoms:

- Video plays fine for 90 days, then suddenly returns 409 Conflict
- Image URLs return `RehydrationRequired` errors
- Customer support tickets that take hours to resolve

Use **Cold** instead (~$0.0036/GB/month). Cold is still online and instantly accessible.

## Storage naming

Storage account names must be lowercase, alphanumeric, ≤24 chars:

```
{org}{project}store{env}     e.g. acmetaskappstoretest
```

If the resulting name exceeds 24 chars, shorten `project` or drop the `store` suffix.

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — `deployStorage: true` toggle
- [deploying-azure-container-apps](../deploying-azure-container-apps/SKILL.md) — when containers need blob access
- [deploying-fc1-flex-consumption-functions](../deploying-fc1-flex-consumption-functions/SKILL.md) — FC1 deployment storage also lives here
- [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) — for the broader cost-guardrail checklist

## Templates

| File | Purpose |
|------|---------|
| [templates/storageAccount-with-lifecycle.bicep](templates/storageAccount-with-lifecycle.bicep) | StorageV2 + lifecycle + CORS + private/public containers |
