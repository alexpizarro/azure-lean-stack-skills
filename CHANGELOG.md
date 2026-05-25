# Changelog

All notable changes to Azure Lean Stack.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/) and this project adheres to [Semantic Versioning](https://semver.org/).

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
