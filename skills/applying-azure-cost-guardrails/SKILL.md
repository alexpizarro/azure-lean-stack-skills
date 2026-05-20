---
name: applying-azure-cost-guardrails
description: Applies Azure cost guardrails to a deployment — verifies consumption-priced SKUs, scale-to-zero on Container Apps, SQL Serverless auto-pause, Log Analytics dailyQuotaGb cap, Storage lifecycle rules, and the free tiers (SWA Free, ACS 100 emails/day, App Insights 5GB/mo). Audits an existing project's Bicep for accidentally provisioned fixed-cost resources and recommends fixes. Use when designing infrastructure to stay near zero cost when idle, auditing a deployment whose bill has grown, or onboarding to azure-cost analysis via Microsoft's azure-skills.
---

# Applying Azure Cost Guardrails

Consumption-first design defaults + a script that audits existing Bicep for cost regressions. This skill is **preventive** — for live cost analysis of a running deployment, compose with Microsoft's [`azure-cost`](https://github.com/microsoft/azure-skills) skill.

## The canonical guardrails

Every project scaffolded by this plugin inherits these defaults. Verify them when auditing.

### 1. SWA Free tier in test, Standard only in prod when needed

```bicep
skuName: environment == 'prod' ? 'Standard' : 'Free'
```

Standard is $9/month per app. Skip it unless you need custom domains, SLA, or the larger function quota.

### 2. SQL Serverless with auto-pause

```bicep
sku: { name: 'GP_S_Gen5_1', tier: 'GeneralPurpose', family: 'Gen5', capacity: 1 }
properties: {
  autoPauseDelay: 15            // minutes before pause
  minCapacity: json('0.5')
  maxSizeBytes: 1073741824      // 1 GB
}
```

Paused = storage cost only (~$0.10/GB/month). First request after pause takes 30–60s.

### 3. Container Apps scale-to-zero

```bicep
scale: {
  minReplicas: 0                // <<< the cost win
  maxReplicas: 3
}
workloadProfileName: 'Consumption'   // never 'Dedicated D4/D8' — those bill per-minute idle
```

Idle = $0. Use `minReplicas: 1` only when cold-start hurts UX.

### 4. Log Analytics `dailyQuotaGb` cap

```bicep
workspaceCapping: { dailyQuotaGb: 1 }
```

Single most important setting. Without it, a logging bug can ingest 100+ GB overnight.

### 5. Storage lifecycle rules

Auto-delete temp blobs, age content through Hot → Cool → Cold. See [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md).

### 6. Storage `Standard_LRS` (not GRS/RAGRS unless DR matters)

```bicep
sku: { name: 'Standard_LRS' }
```

LRS is half the cost of GRS. Use GRS only when a written DR requirement exists.

### 7. GHCR over Docker Hub/ACR for non-secret images

GHCR public = $0. ACR Basic = ~$5/mo. Docker Hub anonymous = rate-limited and fragile.

### 8. ACS Email free tier

100 emails/day free. Stays under cap for verification/password-reset use cases on apps with up to ~3000 active users.

### 9. Function Apps on Consumption (Y1) or Flex Consumption (FC1)

Never on App Service Plans (B1, S1, P1V2) — those bill per-second whether the app is busy or idle. Only acceptable if you've made a deliberate trade for predictable latency.

### 10. No App Insights without `dailyQuotaGb`

A workspace without the cap is a billing accident waiting to happen.

## The audit script

[scripts/audit-sku-overrides.sh](scripts/audit-sku-overrides.sh) greps a Bicep tree for fixed-cost SKUs and red flags. Run it on every PR that touches `infra/`:

```bash
bash skills/applying-azure-cost-guardrails/scripts/audit-sku-overrides.sh infra/
```

Sample output:

```
[FAIL] infra/modules/functionApp.bicep:42 — App Service Plan SKU 'P1V2' detected
[WARN] infra/modules/sql.bicep:30 — SQL tier 'Premium' detected (always-on, expensive)
[WARN] infra/modules/storage.bicep:5 — Storage SKU 'Standard_GRS' detected (verify DR requirement)
[FAIL] infra/modules/aca.bicep:18 — minReplicas: 1 — confirm cold start matters
[INFO] infra/modules/observability.bicep — dailyQuotaGb NOT FOUND — adding one is strongly recommended
```

## Free-tier ceilings (Azure subscription)

These are per-subscription, not per-project. Apps benefit by default:

| Service | Free tier ceiling |
|---------|-------------------|
| Static Web Apps Free | unlimited apps; 100 GB/month bandwidth, 0.5 GB storage/app, 100 managed function executions/sec |
| App Insights ingestion | first 5 GB/month free |
| Log Analytics ingestion | first 5 GB/month free |
| Storage egress | first 100 GB/month free |
| Storage transactions | first 20k free across tiers |
| Functions (Consumption) | 1M requests/month + 400,000 GB-s execution free |
| ACS Email | 100 emails/day free |

Stack these by default; a small project can run essentially free.

## Resources that always cost money

| Resource | Approx monthly cost (idle) |
|----------|---------------------------|
| App Service Plan (B1) | ~$13 |
| App Service Plan (S1) | ~$70 |
| App Service Plan (P1V2) | ~$73 |
| Premium Functions Plan (EP1) | ~$148 |
| SQL Provisioned (S0) | ~$15 |
| Dedicated ACA workload profile (D4) | ~$110 |
| Premium Storage block-blob | ~$0.15/GB just for capacity |
| Reserved network IP | ~$3 |
| Application Gateway | ~$200 |
| API Management Premium | ~$2700 |

If any of these appear in Bicep, there should be a written justification in a comment.

## When breaking the defaults is correct

| Trade | When |
|-------|------|
| Standard tier SWA | Custom domain, SLA, >100 managed function executions/sec |
| `minReplicas: 1` on ACA | Cold-start latency is user-visible and unacceptable |
| Provisioned SQL (S0, S1...) | Sustained query workload where 30–60s pause-resume is unacceptable |
| GRS Storage | Regulator requires geo-redundancy |
| Higher `dailyQuotaGb` | Production with high traffic and structured logging |

Add a Bicep comment explaining the trade-off so a future reader knows it was intentional.

## Composes with

- **Microsoft's [`azure-cost`](https://github.com/microsoft/azure-skills)** — for live cost analysis of running deployments
- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — applies these defaults
- [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md) — lifecycle rules
- [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md) — `dailyQuotaGb`
- [deploying-azure-container-apps](../deploying-azure-container-apps/SKILL.md) — scale-to-zero
