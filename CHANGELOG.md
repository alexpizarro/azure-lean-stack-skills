# Changelog

All notable changes to Azure Lean Stack.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/) and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [2.3.0] — 2026-09-14

Peer-review release: every pinned version re-verified against npm, GitHub releases, Microsoft Learn and `az provider show`; every Bicep template compiles; the field learnings from `trg-directory-*`, `bc-videohub-lite`, `BC Quick Check In` and `count8-website` (May → September 2026) folded in.

### Added

- **New skill:** [`securing-azure-sql-and-storage-with-managed-identity`](skills/securing-azure-sql-and-storage-with-managed-identity/SKILL.md) — Entra-token SQL auth + user-delegation SAS from the compute's system-assigned MI, flag-gated (`SQL_AUTH_MODE` / `STORAGE_AUTH_MODE`) with password/key kept as rollback. Includes the Entra-admin + MI-DB-user + storage-RBAC setup, the async delegation-key priming hook, the Bicep-resets-app-settings durability trap, and a narrower-roles table (custom job-start role, `AcrPull` vs `AcrPush`, keyless OpenAI). Proven in `bc-videohub-lite` (2026-07-17). Default for new FC1 / Container Apps APIs; not applicable to SWA managed functions.
- **Cost Guardrail #15 + `templates/costGuardrails.bicep`** — Action Group + monthly Consumption budget on the RG (50/80/100 % actual + 100 % forecast), optional per-resource budget, and a `Replicas` Minimum > 0 for 1 h "stuck-warm" alert per scale-to-zero Container App. Deploy once out-of-band per environment. Proven in `bc-videohub-lite`.
- **`scripts/check-live-replicas.sh`** — sweeps every Container App in every subscription and reports **running replicas** (never revisions — a revision-based check gave 6/6 false positives), `cooldownPeriod > 300`, `minReplicas > 0`.
- **KEDA cron warm windows** on Container Apps — `warmWindowStart/End/Timezone` params on `containerApp.bicep`, `templates/scale-config.json` for `az rest` PATCH, full write-up in the ACA skill and `scale-to-zero.md`. Replaces "raise the cooldown" (which cost A$56/mo in `bcci-app`) with a ~A$0.02/day window.
- **Container App retirement checklist** and the three Job traps (`--replica-retry-limit 0` silently ignored; `/start` body replaces env; `{template:…}` wrapper silently empty), plus shared cross-subscription ACR guidance.
- **`sqlSku: 'Serverless' | 'Basic'`** on the scaffold's `sqlServer.bicep` / `main.bicep` / parameter files — the Basic switch both steady-traffic projects made.
- **Scaffold now wires `deployStorage` and `deployObservability`** — `infra/modules/storageAccount.bicep` and `applicationInsights.bicep` ship as marked copies of the canonical templates, `main.bicep` deploys them behind the toggles and outputs the App Insights connection string, and the deploy workflows set it on the SWA. The 2.2.0 eval that asserted this now passes against the template.
- **`api/src/functions/health.ts`** ships in the SWA template — shallow by default, `?deep=1` probes SQL, three-state result.
- **`templates/multi-container.yaml`** (was referenced but never shipped), `templates/scripts/ci/install-sqlcmd.sh`, `templates/.nvmrc`.
- **Gotchas #46–#56:** `Azure/functions-action` outage, Kudu quick-succession abort, v4 host not discovering functions from a fresh zip, 503 after Bicep reset app settings, `az acr build` "could not be found" (AcrPush / cross-sub), replica stuck `Activating` on ImagePullFailure (A$420/mo), `--replica-retry-limit 0`, Job start env override, SWA edge overwrites `Authorization`, `gh workflow run` without `--ref`, SQL Server 2025 AVX crash on Apple Silicon. Quick symptom table now covers all 56.
- **Verify-before-promote** rule in the curating skill (two external reviewers produced five wrong P1s from config alone).

### Changed

- **Versions (2026-09-14):** `azure/login` v2 → **v3**, `actions/checkout` / `setup-node` v4 → **v6** (Node 20 actions leave GitHub runners 2026-09-23), **Vite 6 → 8** + `@vitejs/plugin-react` 4 → 6, **mssql 11 → 12** (config objects no longer cloned) + `@types/mssql` 9 → 12, `@azure/functions` ^4.5 → ^4.16, React ^19.3, TypeScript ^5.9, Azurite pinned to 3.37.0. Template lockfiles regenerated. `stack-versions.md` rewritten with a per-resource Bicep API-version table.
- **Bicep API versions** bumped to the newest stable that has types in the `az`-bundled Bicep 0.41 *and* 0.47: `Microsoft.App/*@2025-01-01`, `Microsoft.Web/staticSites@2024-04-01`, `Microsoft.Web/sites|serverfarms@2024-04-01`, `Microsoft.Sql/*@2023-08-01` (was `-preview`), `Microsoft.Storage/*@2024-01-01` (was split 2023-01-01 / 2023-05-01), `Microsoft.OperationalInsights/workspaces@2025-02-01`, `Microsoft.Communication/*@2025-09-01`, `Microsoft.Resources/resourceGroups@2024-03-01`, `CostManagement/query?api-version=2024-08-01`.
- **FC1 is CommonJS, not ESM.** The v1-era "FC1 = `"type": "module"` + `.js` import suffixes" rule was never proven; `bc-videohub-lite`'s FC1 API is CommonJS and Azure Functions' ESM support is still `.mjs`-only preview. `api/` now moves from SWA to FC1 unchanged.
- **FC1 deploys with `az functionapp deployment source config-zip` + restart**, not `Azure/functions-action` (disabled on GitHub 2026-06-05 → 06-10). Architecture Decision #9 codifies "no third-party marketplace action in the deploy path". `flexConsumption.bicep` exposes `instanceMemoryMB` (512 / 2048 / 4096) and pins `alwaysReady: []`.
- **Deploy workflows:** `concurrency` (test cancels, prod never), `--location` from the parameter file, `nullglob` migration loop, sqlcmd via `scripts/ci/install-sqlcmd.sh` (one copy, not three), App Insights wiring, `pr-checks.yml` reads `.nvmrc`. Templates gain `typecheck` scripts so `pr-checks.yml` no longer fails on a fresh scaffold, `engines.node`, and a real `dev:test` script driven by `VITE_PROXY_TARGET`.
- **`staticwebapp.config.json`** template: `platform.apiRuntime: node:22`, full security-header set, no legacy `/*` catch-all route.
- **Guardrail #9** rewritten for FC1 + `alwaysReady`; Y1 Linux Consumption retirement date (2028-09-30) recorded; the App Service B1 "known floor" reconciled as the one documented exception.
- **Audit scripts:** `audit-sku-overrides.sh` storage-lifecycle check could never fire (stray quote) — fixed; adds `cooldownPeriod > 300` and a missing-budget INFO. `audit-cost-antipatterns.sh` no longer flags `?deep=`/`?probe=`-gated health checks; the CI-resurrection check is now a WARN so it gates.
- **OIDC:** `--sdk-auth` → `--json-auth`; branch-guard step and `--ref` for manual dispatch; the temp secrets file is `umask 077` + removed on `trap EXIT`.
- **SWA skill:** hosting decision table now includes App Service B1 (Next.js ISR over the 500 MB SWA ceiling) and Container Apps for Next.js with middleware; managed functions' no-MI / no-Key-Vault limit stated; `Authorization`-header overwrite documented.
- **Curating skill** and `learnings/README.md`: the gitignored-learnings contradiction resolved (learnings are private; only gotcha rows are shared; frontmatter format documented where the scripts expect it).
- Counts and structure fixed everywhere (README said 14 *and* 16 skills; plugin.json said 38+ gotchas; CLAUDE.md tree said v2.0.0).
- `plugin.json` → `2.3.0`; 17 skills; keywords `managed-identity`, `keda-cron`, `cost-alerts`, `budgets`, `vite`, `node-22`.

### Fixed

- `containerAppJob.bicep` did not compile (BCP138: for-expression inside `union()`); `multi-tenant-main.bicep` did not compile (referenced five modules that weren't in the skill). Both compile; every `.bicep` in the pack is now compiled in review.
- **From the independent Codex review of this release:** `sqlcmd` ran without `-b`, so a failed migration reported success (workflows + both migration scripts); the SQL-migration step ran even when `deploySql=false`; `-U sqladmin` was hard-coded although `sqlAdminLogin` is a parameter; `generate-sql-password.sh` used `shuf` (absent on macOS) and `tr | head` under `pipefail` (SIGPIPE) — replaced with a python3 `secrets` generator; `containerAppJob.bicep` accepted `triggerType: 'Event'` but emitted no scale rules (now `eventScaleRules`); `flexConsumption.bicep` documented a role assignment it never created (now `assignHostStorageRole`, default on); `applicationInsights.bicep` `substring(...,0,12)` failed for short base names; the MI runtime sample parsed only `Initial Catalog=` (the scaffold emits `Database=`), needed an undocumented `STORAGE_ACCOUNT_KEY`, and built blob URLs without a `/`; `db_ddladmin` was granted by default (now opt-in); Storage Blob Delegator is documented as required only for container-scoped grants (Data Contributor at account scope already includes `generateUserDelegationKey`); ACS Email was described as "100/day free" — it is $0.00025/email with a 10/hour cap on Azure-managed domains; SWA Free quotas corrected (10 apps, 500 MB total / 250 MB per environment); the frontend template lacked `@types/node` for `vite.config.ts`; `getItems`/`createItem` lacked the documented mock guard; migration loops were not whitespace-safe; `audit-sku-overrides.sh` now exits 3 on WARN-only, checks budget and stuck-warm alert independently, and the anti-pattern audit only excuses a DB health check when the DB call sits *after* a `deep`/`probe` gate, parses the Logic App interval, matches plain `* * * * *`, ignores import lines, and accepts a `RETIRED_RESOURCES` denylist; `check-live-replicas.sh` exits 2 on any failed query instead of reporting zero replicas.
- `database.ts` didn't export `getPool` although the docs imported it.
- `deploying-azure-container-apps/SKILL.md` linked a `multi-container.yaml` that didn't exist.
- `managing-azure-sql-migrations/SKILL.md` claimed the workflows *call* its scripts; they inlined a third copy.
- Placeholder mismatches (`YOUR_PASSWORD` vs `YOUR_SQL_PASSWORD`), template package names still on the pre-rename brand.

### Proven sources

- `bc-videohub-lite` — MI cutover, budgets + stuck-warm alerts, az-CLI zip deploy, `always()` settings restore, SQL Basic, CommonJS FC1, Vite 8.
- `trg-directory-website` — App Service B1 for ISR, cost sentinel, deploy-freshness gate, Kudu/config-zip gotchas, direct-ARM job start, `azure/login@v3` + `checkout@v6`.
- `trg-directory-content-crawl` — HTTP app → Job retirement, structural workflow tests, shared ACR, ImagePullFailure burn.
- `BC Quick Check In` — KEDA cron warm window replacing `cooldownPeriod: 7200`, `az rest` PATCH shape.
- `count8-website` — SWA `Authorization` overwrite, apex-alias DNS cutover.

### Still waiting for a proven project (unchanged from 2.1.0, plus)

- Automation-runbook auto-remediation for a stuck-warm app (`bc-videohub-lite` has it; one project isn't the bar for a template that restarts prod).
- A generic deploy-freshness gate template (`build-info.json` + route probe) — described in the orchestrator, not templated.
- App Service B1 as a pack skill (one project; documented as a hosting-table row and a known floor instead).

---

## [2.2.0] — 2026-05-26

### Added

- **New skill:** [`developing-azure-apps-locally`](skills/developing-azure-apps-locally/SKILL.md) — a fully-offline local dev stack (Docker SQL Server 2022 + Azurite) as the `main`-branch "try" tier of the **local → test → prod** flow. One-command bootstrap (`up.sh`), idempotent local `migrate.sh`, optional `seed-from-test.sh`, Azurite `cors.sh`, a `docker-compose.yml` + `local.settings.json.example`, and an `offline-stack.md` reference (Rosetta/amd64, endpoint-aware SAS URLs, mock mode, `dev:test` trade-off). Proven by `bc-videohub-lite` (`docs/LOCAL-DEV.md`, `scripts/local-dev/*`).
- **Cost Guardrail #11 — "Don't let polling defeat scale-to-zero"** in [`applying-azure-cost-guardrails`](skills/applying-azure-cost-guardrails/SKILL.md): the mechanism (a health endpoint / scheduler that touches the DB keeps SQL Serverless awake 24/7), the serverless-vs-flat-Basic decision rule, and an **advisory-triggers** table telling Claude to warn the user *before* implementing a health endpoint / uptime check / keep-alive / DB-reading scheduler / `minReplicas: 1`.
- **New detection script** [`audit-cost-antipatterns.sh`](skills/applying-azure-cost-guardrails/scripts/audit-cost-antipatterns.sh) — greps app source for DB-querying health/status endpoints and frequent schedulers; exits non-zero so it can gate CI. Validated against the real `trg-directory-website` `status.ts`.
- **Shallow health-check pattern** in [`deploying-azure-static-web-apps`](skills/deploying-azure-static-web-apps/SKILL.md): DB-free `/api/health`, DB check gated behind `?deep=1`.
- **Gotcha #40** (Cost): "SQL Serverless bill higher than expected; DB never pauses" → cause + fix.
- **Scheduler cost warning** in [`scheduling-with-azure-logic-apps-consumption`](skills/scheduling-with-azure-logic-apps-consumption/SKILL.md) — don't point a frequent recurrence at a DB-backed endpoint.
- **2 eval scenarios:** `developing-locally.json`, `cost-antipattern-healthcheck.json`.

### Changed

- **Branch model is now explicitly local → test → prod.** Architecture Decision #0 reframes `main` from "local dev only" to the fully-offline "try" tier backed by `developing-azure-apps-locally`. README and orchestrator routing updated.
- `plugin.json` → `2.2.0`; 16 skills; keywords `local-development`, `azurite`, `offline-stack`.

### Proven sources

- `bc-videohub-lite` — the offline local stack, and the serverless→Basic tier switch (2026-05-23, ~10× cheaper at steady low usage).
- `trg-directory-website` — the cost-overrun cause (`status.ts` queried the DB on every health call while a 5-min scheduler polled it).

---

## [2.1.0] — 2026-05-21

### Added

- **Brand:** plugin renamed from `azure-starter` to **Azure Lean Stack**. Tagline: *"Azure apps that cost nothing when nobody's using them."*
- **New skill:** [`scheduling-with-azure-logic-apps-consumption`](skills/scheduling-with-azure-logic-apps-consumption/SKILL.md) — recurring HTTP triggers and Power-Automate-style flows on Logic Apps Consumption (~$0.22/month at 5-min cadence). Proven by `trg-directory-website`'s recrawl scheduler.
- **New workflow template:** `pr-checks.yml` in `scaffolding-azure-bicep-infrastructure/templates/.github/workflows/`. Typecheck + build + test for frontend + API on every PR. Pattern proven in `trg-directory-website` and `trg-directory-content-crawl`.
- **Workflow checklist pattern** added to the multi-step skills (OIDC, scaffolding, FC1, multi-tenant). Claude copies the checklist into its response and ticks items off — catches skipped steps.
- **Evals** (`evals/`) — three starter JSON scenarios covering orchestrator routing, scaffolding with toggles, and FC1 CLI-fallback diagnostics. Plus a `README.md` describing the format and how to run them across Haiku/Sonnet/Opus.
- **CHANGELOG.md** (this file) — captures the v1 → v2 jump and ongoing changes.
- **`RECIPES.md`** — curated set of proven recipes lifted from real projects, with cost figures.

### Changed

- **Branch-per-environment is now Architecture Decision #0** (was implied, now made explicit and non-negotiable). The orchestrator's SKILL.md leads with it. References lay out the full rationale and the OIDC subject lockdown that makes test SPs structurally unable to deploy to prod.
- **README.md** rewritten end-to-end. Leads with the back story (Lovable burnout → trusted Azure → Claude Code struggle → built this), the cost table, and the quickstart. The v1 README's enterprise-readiness section is preserved at the bottom.
- **CLAUDE.md** updated to reflect the new architecture, brand, and contribution flow (capture learning → review → promote to gotcha).
- **`plugin.json`** description tightened; new keywords (`logic-apps-consumption`, `branch-per-environment`, `microsoft-consulting`, `power-platform-bridge`, etc.).
- **Sharpened skill descriptions** on orchestrator, container-apps, troubleshooting, scaffolding, and OIDC — tighter "what + when" sentences, fewer keyword stuffs.

### Verified-but-not-added (still waiting for a proven project)

- Logic Apps **Standard** — only Consumption is currently proven. Will add when a real project ships on Standard.
- Azure AI Foundry Agents — no reference project uses Foundry's agents service yet.
- Budget alerts (`Microsoft.Consumption/budgets`).
- Cosmos DB Serverless.
- Azure AI Search.
- Container Apps Add-ons (managed Postgres/Redis/Kafka).
- APIM Consumption tier.

The skill pack will only add these once a real project demonstrates the pattern, per the "every pattern proven in a project" rule.

---

## [2.0.0] — 2026-05-20

### Changed (BREAKING)

Decomposed the single `azure-starter` skill into an orchestrator + 13 single-purpose sub-skills (gerund-form names). All previous `/azure-starter <action>` argument routing is gone — Claude now selects the right sub-skill based on the task.

### Added

- **14 skills** with one-level progressive disclosure:
  - `orchestrating-azure-deployments`
  - `scaffolding-azure-bicep-infrastructure`
  - `configuring-azure-oidc-for-github-actions`
  - `managing-azure-sql-migrations`
  - `deploying-azure-static-web-apps`
  - `deploying-fc1-flex-consumption-functions`
  - `deploying-azure-container-apps`
  - `optimizing-azure-blob-storage-cost` (NEW)
  - `adding-azure-communication-services-email`
  - `instrumenting-azure-app-insights` (NEW)
  - `scaffolding-multi-tenant-azure-apps` (NEW)
  - `applying-azure-cost-guardrails` (NEW)
  - `diagnosing-azure-deployment-failures`
  - `curating-azure-deployment-learnings` (NEW META-SKILL)
- **7 executable scripts** replacing manual bash blocks: OIDC setup (3), SQL migrations (2), cost audit (1), learnings curation (3).
- **Bicep templates** moved into per-skill `templates/` directories (storageAccount-with-lifecycle, applicationInsights, multi-tenant-main, ACS, managedEnv, containerApp, containerAppJob).
- **Composition with Microsoft's `azure-skills` plugin** declared explicitly in `composition-with-azure-skills.md`.
- **Storage lifecycle rules** (Hot→Cool@60d→Cold@180d) lifted from `bc-videohub-lite`.
- **Multi-tenant pattern** (single `tenant` param, one RG per tenant) lifted from `bc-videohub-lite`.
- **ACA Jobs + multi-container sidecars + shared managed environment** patterns lifted from `bc-videohub-lite` and `trg-directory-content-crawl`.
- **Workspace-based App Insights with `dailyQuotaGb` cap** lifted from `trg-directory-website`.

### Removed

- Old monolithic `skills/azure-starter/` skill (preserved at tag `v1.0.0` as rollback marker).
- Root-level `template/` directory (content distributed into per-skill `templates/`).
- Root-level `ARCHITECTURE.md`, `DEPLOY.md`, `FC1-DEPLOYMENT.md`, `PATTERNS.md` (content distributed into skill references).

### Migration from v1

If you were on v1.0.0, no action required to keep using v1 — pin to `@v1.0.0` in your install command. To upgrade:

1. `claude plugin install alexpizarro/azure-lean-stack-skills@v2.0.0` (or `@latest`)
2. The old `/azure-starter scaffold` etc. argument-routed commands are gone. Instead, describe what you want naturally — Claude routes to the right sub-skill.
3. If you generated a v1 project, its files are unchanged. The v2 plugin works with v1-shaped projects identically.

---

## [1.0.0] — 2026-03-26

Final monolithic release. Single `azure-starter` skill with `$ARGUMENTS` routing (`scaffold | setup | deploy | troubleshoot | upgrade`). Six reference files. 37 gotchas catalogued. Root-level `template/` directory as the canonical project shape.

Tagged at commit `bae6989` ("Tune SQL Serverless defaults for lowest cost on low-volume apps").
