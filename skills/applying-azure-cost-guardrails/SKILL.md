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

### 11. Don't let polling defeat scale-to-zero

The most expensive mistake in a lean stack — it silently turns a $0.10/month resource into a 24/7 bill. **A scale-to-zero resource only saves money if it actually goes idle.** Anything that touches it on a steady cadence keeps it awake:

- **SQL Serverless** auto-pauses after `autoPauseDelay` minutes of *no connections*. A health/status endpoint that runs a query, an uptime monitor, or a scheduler hitting a DB-backed endpoint resets that timer on every call. The DB never pauses → you pay for compute continuously — *more* than a small provisioned tier would cost.
- **Container Apps** with `minReplicas: 0` scale up on traffic. A frequent keep-alive ping keeps a replica warm 24/7.

**Proven failure:** `trg-directory-website`'s `status.ts` health endpoint ran `SELECT COUNT(*) FROM clinics …` on every call, and a 5-minute Logic App scheduler polled it. The serverless DB (`autoPauseDelay: 15`) never paused and billed compute around the clock.

**Decision rule — serverless vs flat Basic:**

| Access pattern | Cheapest tier |
|----------------|--------------|
| Genuinely bursty / idle (real gaps > the auto-pause delay) | **SQL Serverless** `GP_S_Gen5_1` — storage-only when paused |
| Steady cadence / polled / small DB (metadata-scale) | **Flat Basic** (`Basic` tier, 5 DTU, 2 GB) — ~$5/mo, no cold-start, no per-second compute |

If a DB is small and hit regularly, serverless-kept-awake costs *more* than flat Basic **and** adds cold-start latency. `bc-videohub-lite` switched `GP_S_Gen5_1` → Basic on 2026-05-23 for exactly this reason (~10× cheaper at its ~5h/day usage). Basic-tier alternative:

```bicep
// Flat ~$5/month, always-on, no auto-pause cold-start. Use when the DB is
// small and accessed on a steady cadence (so serverless would rarely pause).
resource db 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  name: databaseName
  location: location
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648   // 2 GB (Basic ceiling)
    requestedBackupStorageRedundancy: 'Local'
  }
}
```

**The fix when you must keep the poll:** decouple it from the DB — see the advisory triggers below and the shallow health-check pattern in [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md).

## Advisory triggers — warn the user before they cause an overrun

When the user asks for any of the following against a project with a scale-to-zero resource, **stop and warn them first**, then implement the cheaper option:

| User asks for… | Warn that… | Suggest |
|----------------|-----------|---------|
| "Add a health/status endpoint that reports DB status" | A DB query on every health call keeps SQL Serverless awake 24/7 | Shallow DB-free `/api/health`; gate the DB check behind `?deep=1` |
| "Add an uptime check / monitor / ping" | Frequent pinging of a DB-backed endpoint defeats auto-pause | Point the monitor at a DB-free endpoint |
| "Poll the API / DB every N minutes" / "keep the database warm" | "Keeping warm" = paying 24/7; this caused a real overrun | If you truly need always-on, switch to flat Basic (~$5/mo) — cheaper than kept-awake serverless |
| "Add a scheduler that reads from the DB" | A Logic App recurrence hitting a DB endpoint keeps the DB awake | Target a DB-free endpoint, or accept always-on and use Basic tier |
| "Set `minReplicas: 1`" on ACA | Always-warm replica ≈ $5/mo; only worth it if cold start is user-visible | Confirm the cold-start UX justifies the cost |

## The audit scripts

[scripts/audit-sku-overrides.sh](scripts/audit-sku-overrides.sh) greps a Bicep tree for fixed-cost SKUs and red flags. Run it on every PR that touches `infra/`:

```bash
bash skills/applying-azure-cost-guardrails/scripts/audit-sku-overrides.sh infra/
```

[scripts/audit-cost-antipatterns.sh](scripts/audit-cost-antipatterns.sh) greps **app source** for Guardrail-#11 defeat patterns — health/status endpoints that query the DB, and frequent schedulers that may keep a serverless DB awake. Run it on every PR that touches `api/` or scheduler definitions:

```bash
bash skills/applying-azure-cost-guardrails/scripts/audit-cost-antipatterns.sh .
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
