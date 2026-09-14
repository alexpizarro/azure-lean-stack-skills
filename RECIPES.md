# Recipes

Working Azure patterns from real production projects. Every recipe here has a corresponding template / script in the skill pack and a source project that proves it.

**The rule:** if a recipe is in this file, it ships in at least one real project. Nothing is fabricated.

---

## 1. Recurring scheduler — $0.22/month

**Pattern:** Azure Logic App (Consumption tier) that POSTs to an HTTP endpoint on a recurring cadence with a shared-secret header.

**Use for:** cache invalidation, heartbeat pings, recrawl ticks, scheduled cleanup, lightweight Power-Automate-style backend flows.

**Cost:** ~$0.22/month at 5-minute cadence (8,640 actions × $0.000025).

**Files:**
- Bicep: [`skills/scheduling-with-azure-logic-apps-consumption/templates/recurring-http-scheduler.bicep`](skills/scheduling-with-azure-logic-apps-consumption/templates/recurring-http-scheduler.bicep)
- Script (one-shot): [`skills/scheduling-with-azure-logic-apps-consumption/scripts/create-recurring-scheduler.sh`](skills/scheduling-with-azure-logic-apps-consumption/scripts/create-recurring-scheduler.sh)
- Skill: [`scheduling-with-azure-logic-apps-consumption`](skills/scheduling-with-azure-logic-apps-consumption/SKILL.md)

**Proven in:** `trg-directory-website` (recrawl scheduler — 5 min cadence, POSTs to `/api/_internal/process-recrawl`).

---

## 2. Multi-container app with sidecar — scale-to-zero

**Pattern:** Azure Container App with two containers in the same replica — a primary FastAPI service and a headless-browser sidecar — sharing localhost.

**Use for:** apps that need an embedded heavy dependency (headless browser, vector DB, local cache) but don't justify a managed service.

**Cost:** $0 when idle (`minReplicas: 0`). Active cost = sum of all containers' CPU/memory at consumption rates.

**Files:**
- Bicep base: [`skills/deploying-azure-container-apps/templates/containerApp.bicep`](skills/deploying-azure-container-apps/templates/containerApp.bicep)
- YAML for multi-container: see [`sidecar-pattern.md`](skills/deploying-azure-container-apps/references/sidecar-pattern.md)
- Skill: [`deploying-azure-container-apps`](skills/deploying-azure-container-apps/SKILL.md)

**Proven in:** `trg-directory-content-crawl` (enrichment FastAPI + crawl4ai sidecar, both pinned versions). Cost while crawling: ~$0.05–0.20 per crawl run depending on volume.

---

## 3. Multi-tenant SaaS on a shared subscription

**Pattern:** One Bicep file with a `tenant` parameter that drives the resource-group name and every resource name. Adding a tenant = copy the parameter file, set the new slug, deploy.

**Use for:** B2B SaaS with 5–100 customers needing isolation but not separate billing.

**Cost:** Per-tenant cost = sum of the tenant's resources. Consumption defaults keep this low ($5–$30/month/tenant for typical low-volume apps).

**Files:**
- Bicep: [`skills/scaffolding-multi-tenant-azure-apps/templates/multi-tenant-main.bicep`](skills/scaffolding-multi-tenant-azure-apps/templates/multi-tenant-main.bicep)
- Skill: [`scaffolding-multi-tenant-azure-apps`](skills/scaffolding-multi-tenant-azure-apps/SKILL.md)

**Proven in:** `bc-videohub-lite` (multi-school deployment — single Bicep, per-school RG, per-school SQL/Storage/ACA).

---

## 4. Container Apps Job — scheduled batch / run-to-completion

**Pattern:** `Microsoft.App/jobs` (not Container App) with `Manual` or `Schedule` trigger. Runs on demand, scales to zero by design (no idle cost — a Job only runs when triggered).

**Use for:** batch processing, full-resync, scheduled crawls, queue-driven workers.

**Cost:** Pay only for actual run time at consumption rates. A 5-minute job run consumes ~$0.05 at 2 vCPU / 4 GiB.

**Files:**
- Bicep: [`skills/deploying-azure-container-apps/templates/containerAppJob.bicep`](skills/deploying-azure-container-apps/templates/containerAppJob.bicep)
- Reference: [`aca-jobs.md`](skills/deploying-azure-container-apps/references/aca-jobs.md)

**Proven in:** `bc-videohub-lite` (cloud full-resync job — manual trigger, takes per-run inputs via `--env-vars`, uses the same image as the local pipeline for parity).

---

## 5. Blob storage with lifecycle ageing (media-safe)

**Pattern:** StorageV2 + lifecycle rules: delete temp blobs at 7 days, age content Hot → Cool@60d → Cold@180d. **Never `tierToArchive`** — content stays instantly accessible.

**Use for:** any app storing user-generated media (video, large images, exports) where retention exceeds 60 days.

**Cost:** Hot ~$0.02/GB/mo, Cool ~$0.01/GB/mo, Cold ~$0.0036/GB/mo. A 100 GB workload with most data aged to Cold: ~$1/month storage.

**Files:**
- Bicep: [`skills/optimizing-azure-blob-storage-cost/templates/storageAccount-with-lifecycle.bicep`](skills/optimizing-azure-blob-storage-cost/templates/storageAccount-with-lifecycle.bicep)
- Skill: [`optimizing-azure-blob-storage-cost`](skills/optimizing-azure-blob-storage-cost/SKILL.md)

**Proven in:** `bc-videohub-lite` (videos + processor-jobs + branding containers; videos age Hot→Cool@60d→Cold@180d; processor-jobs blobs auto-delete at 7d).

---

## 6. Branch-per-environment CI/CD with OIDC

**Pattern:** One git branch = one isolated Azure resource group. `main` is local-dev only (no Azure environment). `test` → test RG. `production` → prod RG. Each environment has its own OIDC-federated service principal bound to the branch's `refs/heads/{branch}` subject.

**Use for:** every project. This is the deployment model.

**Cost:** $0 — GitHub Actions free tier for public/test repos; pay-per-minute for private repos at standard GitHub Actions rates.

**Files:**
- Setup scripts: [`skills/configuring-azure-oidc-for-github-actions/scripts/`](skills/configuring-azure-oidc-for-github-actions/scripts/)
- Workflows: [`skills/scaffolding-azure-bicep-infrastructure/templates/.github/workflows/`](skills/scaffolding-azure-bicep-infrastructure/templates/.github/workflows/)
- Skills: [`configuring-azure-oidc-for-github-actions`](skills/configuring-azure-oidc-for-github-actions/SKILL.md), [`scaffolding-azure-bicep-infrastructure`](skills/scaffolding-azure-bicep-infrastructure/SKILL.md)

**Proven in:** `bc-videohub-lite`, `trg-directory-website`, `trg-directory-content-crawl` (all three).

---

## 7. SWA + SQL Serverless + Application Insights — the lean web stack

**Pattern:** React frontend + managed Azure Functions API + SQL Serverless (auto-pause) + workspace-based App Insights with `dailyQuotaGb` cap. All free or near-free tiers.

**Use for:** any CRUD-style web app, especially client prototypes.

**Cost:** ~$0–$5/month at low traffic. SWA Free, SQL ~$0.10/mo when paused, App Insights <$2/mo with 1GB daily cap.

**Files:**
- Bicep: [`skills/scaffolding-azure-bicep-infrastructure/templates/infra/main.bicep`](skills/scaffolding-azure-bicep-infrastructure/templates/infra/main.bicep)
- App Insights: [`skills/instrumenting-azure-app-insights/templates/applicationInsights.bicep`](skills/instrumenting-azure-app-insights/templates/applicationInsights.bicep)
- App code: [`skills/deploying-azure-static-web-apps/templates/`](skills/deploying-azure-static-web-apps/templates/)

**Proven in:** `trg-directory-website` (full SaaS with auth, SQL data, API endpoints, observability).

---

## 8. Container App Job for SWA deploys (advanced)

**Pattern:** Use an Azure Container Apps Job (not GitHub-hosted runner) to perform the actual SWA deploy. Adds managed identity, private artefact storage, and IP allowlisting. Useful for compliance-sensitive deployments where the GitHub runner shouldn't be the deploy boundary.

**Cost:** Pay only for the Job's run time during a deploy. A typical SWA deploy job: ~$0.01 per deploy.

**Files:**
- Bicep reference: see `infra/modules/deployJob.bicep` pattern in `trg-directory-website` (full implementation lives in the source project)

**Proven in:** `trg-directory-website` (per its `deployJob.bicep` module — full implementation with ACR pull, managed identity, role assignments).

**Note:** This is an advanced pattern. Most projects can stick with the standard GitHub-runner deploy. Use this only when there's a real reason (private network, audit trail, compliance).

---

## 9. Scale-to-zero warm window — KEDA cron instead of a longer cooldown

**Pattern:** Leave `cooldownPeriod` at 300 s and add a KEDA `cron` scale rule (IANA timezone, `desiredReplicas: 1`) for the hours users actually arrive. KEDA takes `max(rules)`, so HTTP still scales inside the window and the app sleeps at 0 outside it.

**Use for:** any Container App with a predictable busy window (a weekly class night, office hours) where cold starts are user-visible.

**Cost:** ~A$0.02/day for a Tuesday-evening window. The alternative it replaced — `cooldownPeriod: 7200` — was A$1.87/day (A$56/mo) for an app serving 26 requests per 8 hours.

**Files:**
- Bicep: [`skills/deploying-azure-container-apps/templates/containerApp.bicep`](skills/deploying-azure-container-apps/templates/containerApp.bicep) (`warmWindowStart` / `warmWindowEnd` / `warmWindowTimezone`)
- `az rest` PATCH body: [`skills/deploying-azure-container-apps/templates/scale-config.json`](skills/deploying-azure-container-apps/templates/scale-config.json)
- Reference: [`scale-to-zero.md`](skills/deploying-azure-container-apps/references/scale-to-zero.md)

**Proven in:** `BC Quick Check In` (`bcci-app`, 2026-07-30 → measured in billing).

---

## 10. Azure-native cost backstop — budget + stuck-warm alert

**Pattern:** One Bicep module per environment resource group: Action Group → monthly Consumption budget (50/80/100 % actual + 100 % forecast) → a `Replicas` Minimum > 0 for 1 h metric alert on every scale-to-zero Container App. Deployed once, out-of-band, from an owner session (budgets need Cost Management permissions the CI SP doesn't have).

**Use for:** every environment that has a Container App or any resource that can silently go always-on.

**Cost:** ~US$0.10/alert rule/month; budgets are free.

**Files:**
- Bicep: [`skills/applying-azure-cost-guardrails/templates/costGuardrails.bicep`](skills/applying-azure-cost-guardrails/templates/costGuardrails.bicep)
- Live sweep: [`skills/applying-azure-cost-guardrails/scripts/check-live-replicas.sh`](skills/applying-azure-cost-guardrails/scripts/check-live-replicas.sh)
- Skill: [`applying-azure-cost-guardrails`](skills/applying-azure-cost-guardrails/SKILL.md) Guardrails #12–#15

**Proven in:** `bc-videohub-lite` (RG budget + per-resource OpenAI budget + stuck-warm alerts on a GPU app and two CPU twins).

---

## 11. Managed identity for SQL + Blob — secretless runtime, one-flag rollback

**Pattern:** The Function App's system-assigned MI authenticates to Azure SQL (`azure-active-directory-default`) and signs user-delegation SAS for Blob. Both paths are behind env flags that default to the legacy password/key path, so the code ships as a no-op and each resource is cut over (and rolled back) independently.

**Use for:** any FC1 / Container Apps API that talks to SQL or Blob. Not SWA managed functions (no MI there).

**Cost:** $0 — managed identity is free. Removes two rotation liabilities.

**Files:**
- Skill: [`securing-azure-sql-and-storage-with-managed-identity`](skills/securing-azure-sql-and-storage-with-managed-identity/SKILL.md)
- Code: [`references/runtime-code-patterns.md`](skills/securing-azure-sql-and-storage-with-managed-identity/references/runtime-code-patterns.md)
- SQL: [`templates/setup-mi-db-user.sql`](skills/securing-azure-sql-and-storage-with-managed-identity/templates/setup-mi-db-user.sql), [`scripts/create-mi-db-user.cjs`](skills/securing-azure-sql-and-storage-with-managed-identity/scripts/create-mi-db-user.cjs)

**Proven in:** `bc-videohub-lite` (2026-07-17, both flags on in prod; sqladmin kept for migrations and break-glass).

---

## Recipe template (for adding new ones)

When a real project proves a new pattern, add it here with this shape:

```markdown
## N. Title — one-line summary + cost figure

**Pattern:** what it is in one sentence

**Use for:** when to reach for it

**Cost:** dollar figure or range

**Files:**
- Bicep: [path]
- Script: [path]
- Skill: [path]

**Proven in:** {project} ({brief context — what the project does with it})
```

If a pattern isn't proven in a real project, don't add it. Capture it as a *learning* via [`curating-azure-deployment-learnings`](skills/curating-azure-deployment-learnings/SKILL.md) and promote it once a real project uses it.
