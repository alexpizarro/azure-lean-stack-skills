---
name: applying-azure-cost-guardrails
description: Applies Azure cost guardrails to a deployment — consumption-priced SKUs, Container Apps that really scale to zero (cooldownPeriod, wake vectors, CI resurrection), SQL Serverless vs flat Basic, Log Analytics dailyQuotaGb cap, Storage lifecycle rules, free tiers, and the Azure-native backstop (Consumption budget + stuck-warm Replicas alert). Ships three audit scripts (Bicep SKUs, app-source anti-patterns, live replica sweep) and a costGuardrails.bicep template. Use when designing infrastructure to stay near zero cost when idle, auditing a deployment whose bill has grown, retiring a resource, or proving a cost fix in billing.
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

### 8. ACS Email — cheap, but not free

ACS Email is pay-as-you-go: **US$0.00025 per email + US$0.00012 per MB** (no free allowance). The `100` you may remember is a **rate limit**, not a free tier: an Azure-managed domain is capped at 10 emails/hour (not raisable); a verified custom domain at 100/hour / 30 per minute (raisable by support ticket). 5,000 transactional emails a month ≈ US$1.25. Use a custom domain for anything beyond a prototype.

### 9. Function Apps on Flex Consumption (FC1) with `alwaysReady: []`

Never on App Service Plans (B1, S1, P1V2) — those bill per-second whether the app is busy or idle — unless you've made a deliberate, documented trade (see "Known floors" under #14: a Next.js ISR site that outgrew SWA's 500 MB ceiling on a B1 shared with its Function App is the one proven case). Linux Consumption (Y1) is retiring 2028-09-30 and gets no new language versions; use FC1. On FC1 keep `alwaysReady: []` — always-ready instances bill continuously — and pick the smallest `instanceMemoryMB` that fits (512 MB is GA).

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

If a DB is small and hit regularly, serverless-kept-awake costs *more* than flat Basic **and** adds cold-start latency. `bc-videohub-lite` switched `GP_S_Gen5_1` → Basic on 2026-05-23 for exactly this reason (~10× cheaper at its ~5h/day usage). The scaffold's `sqlServer.bicep` exposes this as `sqlSku: 'Serverless' | 'Basic'` (set it in the parameter file). What it emits for Basic:

```bicep
// Flat ~$5/month, always-on, no auto-pause cold-start. Use when the DB is
// small and accessed on a steady cadence (so serverless would rarely pause).
resource db 'Microsoft.Sql/servers/databases@2023-08-01' = {
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

### 12. Scale-to-zero *configuration* is not scale-to-zero *behaviour*

`minReplicas: 0` in Bicep proves nothing. Check **live replica counts** — an app can sit
at 1 replica 24/7 with a perfectly correct config. Three independent causes, all silent:

**(a) Inbound wake vectors — something keeps calling it.** Guardrail #11 covers *your
polling keeping the DB awake*; this is the mirror image — *your UI and health checks
keeping the container awake*. The recurring triad:

| Wake vector | Why it's easy to miss |
|---|---|
| An **anonymous** `/api/status` that health-checks a downstream service | Every bot, uptime check and deploy smoke test wakes it |
| A status page with `setInterval(30_000)` | **2,880 hits/day per open tab** — and it keeps polling in a backgrounded tab |
| A scheduler that **wakes the service, then checks whether there's work** | An *empty* queue tick still forces a scale-from-zero |

Fixes: make downstream probes **opt-in + authenticated**, gate UI polling on tab
visibility, and **peek the queue before waking anything**. Make health responses
**three-state** (`healthy: true | false | null`) — with a boolean, a service you never
probed has to be reported as either healthy (a lie) or down (a false outage).

**(b) `cooldownPeriod` — "the second `minReplicas`".** If `cooldownPeriod` exceeds your
mean inter-arrival time, the alive window never closes and the app is always-on:

```
78 req/day  = 1 request every ~18 min
cooldownPeriod: 7200  → each request extends the window 120 min → NEVER scales down
cooldownPeriod: 300   → 18 min gap > 5 min → scales to zero between requests
```

Proven: `bcci-app` billed ~A$2/day to serve **26 requests per 8 hours**, purely from a
7200s cooldown. Raising cooldown to "avoid cold starts" is functionally `minReplicas: 1`,
but invisible in the config people review. **Flag any value > 300.**

**(c) Retiring it in Azure but not in CI** — see Guardrail #13.

To actually stop the spend on an app you're retiring, **deactivate every revision**
(scaling down or updating leaves it active and re-provisions):

```bash
az containerapp revision deactivate -n <app> -g <rg> --revision <rev>
```

Verify **all** revisions are `Inactive` with 0 replicas — a retired app usually has
several, and the newest isn't always the only active one. For anything async, prefer a
Container Apps **Job** (`--trigger-type Manual`): no ingress means no wake surface at all.

> **A false rule to reject:** *"an ACA with external ingress can't scale to zero because
> platform health probes count as ingress traffic."* This is **wrong** — measured against
> a real estate, 9 of 10 apps with external ingress, `minReplicas: 0`, no VNet and default
> cooldown sat at **0 replicas**. It's a seductive explanation because it fits a single
> pinned app, and acting on it pushes teams off scale-to-zero onto always-on SKUs — the
> opposite of the fix. When one app is pinned and its peers aren't, the cause is in that
> app, not the platform.

### 13. Retiring a resource means retiring it from CI too

The most expensive failure mode isn't provisioning something costly — it's **your own
pipeline resurrecting something you deleted**. A deploy workflow that runs
`az containerapp update` against a retired app (or `curl`s its `/health` to "verify the
deploy") recreates and re-wakes it on **every single deploy**.

Proven: the TRG enrichment app came back **twice** this way — and the prod workflow's step
targeted an already-deleted resource, so it could only ever fail, and had been failing
unnoticed.

**Retirement checklist:**
1. Deactivate all revisions (above)
2. Remove it from Bicep/IaC
3. **`grep` the CI workflows for the resource name** ← the step everyone skips
4. Add a structural test asserting the workflows no longer reference it
5. Prove it in **billing**, not config (Guardrail #14)

### 14. Prove a cost fix in billing, not in config

Config screenshots are what let an idle burn recur three times — every incident *looked*
fixed. The only acceptable proof is per-resource daily billing showing the drop.

**`az costmanagement query` does not exist.** Use the REST API:

```bash
az rest --method post --subscription "$SUB" \
  --uri "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.CostManagement/query?api-version=2024-08-01" \
  --body @query.json
```

```json
{ "type": "ActualCost", "timeframe": "Custom",
  "timePeriod": { "from": "2026-07-01", "to": "2026-07-29" },
  "dataset": { "granularity": "Daily",
    "aggregation": { "cost": { "name": "Cost", "function": "Sum" } },
    "grouping": [ { "type": "Dimension", "name": "ResourceId" } ] } }
```

`Daily` granularity grouped by `ResourceId` is what turns "we think it's fixed" into a
number: **A$7.93 / 8.12 / 7.89 / 7.89 / 7.92 per day → A$0.10**. Note the reporting lag —
the last day in a window is partial and reads low; don't call a fix proven off it.

**Sweep every subscription, not just the one you're looking at.** A leak framed as "a
$PROJECT bug" hid an identical one in an unrelated product (A$207/30d of Container Apps in
a different subscription). Scope cost alerts at the **tenant/management-group** level.

**Known floors — don't report these as leaks.** An audit that flags the irreducible
baseline trains people to ignore it:

| Looks expensive | Reality |
|---|---|
| 2 × B1 App Service + 2 × SQL Basic ≈ A$56/mo | The floor for a Next.js ISR site that outgrew SWA's 500 MB ceiling (`trg-directory-website`). A Function App **shares** the B1 plan — not an extra charge. This is the one accepted exception to Guardrail #9; it is documented in the Bicep. |
| Log Analytics / Azure Monitor | Was 0.8% of spend. Uncapped `dailyQuotaGb` is a *dormant risk* worth capping, not a current tax |

The Cost Management query needs **Cost Management Reader on the subscription** — the Contributor-only deploy SP does not have it. A daily `cost-sentinel` workflow that runs this query and fails above a per-service daily threshold catches a leak in one day; budgets lag 8–24 h. Make "cannot check" a distinct exit code (2) so a broken check never reads as "cost fine", and threshold on **yesterday's daily** cost, not month-to-date — MTD accumulates sunk spend and re-fires every day for an already-fixed incident.

### 15. Ship the Azure-native backstop: a budget and a stuck-warm alert

Everything above depends on someone running a script. The backstop that needs no human and no repo is [templates/costGuardrails.bicep](templates/costGuardrails.bicep): an Action Group, a **monthly Consumption budget on the resource group** (50 / 80 / 100 % actual + 100 % forecast), an optional second budget filtered to one high-risk resource (an OpenAI account, a GPU app), and a **`Replicas` Minimum > 0 for 1 h** metric alert for every scale-to-zero Container App. The alert fires in an hour; the budget in a day. Deploy it **out-of-band at RG scope from an owner session** — `Microsoft.Consumption/budgets` needs Cost Management permissions the CI SP does not have, and a permission gap must never break a deploy.

```bash
az deployment group create -g <org>-<project>-rg-<env> \
  --template-file skills/applying-azure-cost-guardrails/templates/costGuardrails.bicep \
  --parameters baseName=<org>-<project> environment=<env> ownerEmail=<you> \
               budgetAmount=30 startDate=$(date +%Y-%m-01) scaleToZeroApps='["<org>-<project>-aca-<env>"]'
```

Proven: `bc-videohub-lite` (RG budget + per-resource OpenAI budget + stuck-warm alerts on three apps, plus an Automation runbook that restarts a pinned app — not in the pack yet).

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

Three scripts, three layers. Wire the first two into `pr-checks.yml`; run the third by hand or from a daily workflow. Exit codes: `audit-sku-overrides.sh` → 1 on FAIL, 3 on WARN-only, 0 clean (gate on 1, or on `!= 0` to be strict); `audit-cost-antipatterns.sh` → 1 on any WARN; `check-live-replicas.sh` → 1 on findings, **2 when a query failed** (indeterminate — never treat as clean).

**[scripts/audit-sku-overrides.sh](scripts/audit-sku-overrides.sh)** — static, greps a Bicep tree for fixed-cost SKUs, `minReplicas > 0` without a justifying comment, `cooldownPeriod > 300`, missing `dailyQuotaGb`, missing lifecycle rules, and Container Apps with no budget / stuck-warm alert. Run on every PR that touches `infra/`:

```bash
bash skills/applying-azure-cost-guardrails/scripts/audit-sku-overrides.sh infra/
```

```
[FAIL] infra/modules/functionApp.bicep:42 — Fixed-cost App Service Plan SKU detected — bills 24/7, even idle
[WARN] infra/modules/aca.bicep:18 — minReplicas > 0 — confirm cold start matters (add a comment if intentional)
[WARN] infra/modules/aca.bicep:31 — cooldownPeriod: 7200s (> 300 default) … functionally minReplicas: 1 (Guardrail #12b)
[INFO] infra/modules/observability.bicep:0 — Log Analytics workspace without dailyQuotaGb cap — strongly recommended
```

**[scripts/audit-cost-antipatterns.sh](scripts/audit-cost-antipatterns.sh)** — static, greps **app source and workflows** for the Guardrail #11–#13 defeat patterns: DB-querying health endpoints (unless gated behind `?deep=`/`?probe=`), sub-15-min schedulers, `cooldownPeriod > 300`, `setInterval` polling without a visibility gate, anonymous health endpoints probing a downstream service, and deploy workflows that update or health-curl a Container App. Run on every PR that touches `api/`, the frontend, or `.github/workflows/`:

```bash
bash skills/applying-azure-cost-guardrails/scripts/audit-cost-antipatterns.sh .
```

**[scripts/check-live-replicas.sh](scripts/check-live-replicas.sh)** — live, reads **running replicas** (never revisions) for every Container App in every subscription and flags anything with replicas, `cooldownPeriod > 300`, or `minReplicas > 0`. The static audits prove the config; only this proves the behaviour (Guardrail #12).

```bash
bash skills/applying-azure-cost-guardrails/scripts/check-live-replicas.sh            # all enabled subscriptions
bash skills/applying-azure-cost-guardrails/scripts/check-live-replicas.sh <sub-id>   # one
```

## Free-tier ceilings (Azure subscription)

These are per-subscription, not per-project. Apps benefit by default:

| Service | Free tier ceiling |
|---------|-------------------|
| Static Web Apps Free | 10 apps/subscription; 100 GB/month bandwidth (no overage — hard stop); 500 MB total storage per app, 250 MB per environment, 3 preview environments, 2 custom domains |
| App Insights ingestion | first 5 GB/month free |
| Log Analytics ingestion | first 5 GB/month free |
| Storage egress | first 100 GB/month free |
| Storage transactions | first 20k free across tiers |
| Functions (Consumption) | 1M requests/month + 400,000 GB-s execution free |
| ACS Email | none — $0.00025/email; 10/hour cap on Azure-managed domains |

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

## Templates

| File | Purpose |
|------|---------|
| [templates/costGuardrails.bicep](templates/costGuardrails.bicep) | Action Group + RG Consumption budget (+ optional per-resource budget) + `Replicas` stuck-warm alert per scale-to-zero Container App. Deploy out-of-band at RG scope. |

## Composes with

- **Microsoft's [`azure-cost`](https://github.com/microsoft/azure-skills)** — for live cost analysis of running deployments
- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — applies these defaults
- [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md) — lifecycle rules
- [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md) — `dailyQuotaGb`
- [deploying-azure-container-apps](../deploying-azure-container-apps/SKILL.md) — scale-to-zero
