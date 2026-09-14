---
name: diagnosing-azure-deployment-failures
description: Matches Azure deploy / CI / runtime failures against 56 documented gotchas with verified fixes (BCP258, AADSTS70021, sqlcmd-not-found, FC1-CLI-silent-fallback, functions-action outage, Kudu quick-succession abort, ACS dataLocation quirks, SSE timeouts, Container Apps idle-burn, SWA Authorization-header overwrite, and more). Delegates to Microsoft's azure-diagnostics for live log/metric queries. Use when a deploy fails, a deployed app misbehaves, a bill jumps, or a CI step errors.
---

# Diagnosing Azure Deployment Failures

Lookup-first triage against documented gotchas. If the symptom doesn't match a known entry, escalate to Microsoft's [`azure-diagnostics`](https://github.com/microsoft/azure-skills) for live log/metric queries.

## How to use this skill

1. Get the failing symptom (error code, stack trace, observed behaviour)
2. Match against the table below
3. Apply the documented fix
4. If no match, see [references/gotchas.md](references/gotchas.md) for the full catalogue
5. If still no match, capture a new gotcha via [curating-azure-deployment-learnings](../curating-azure-deployment-learnings/SKILL.md)

## Quick symptom table

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `BCP258: sqlAdminPassword missing` | Using `.bicepparam` instead of `.parameters.json` | Keep params as `.parameters.json`; use `@` prefix |
| `LocationNotAvailableForResourceType` for SWA | `australiaeast` not supported | Hard-code `swaLocation = 'eastasia'` |
| `Multiple files found matching pattern *.sql` | `azure/sql-action` accepts only one file | Replace with `sqlcmd` bash loop |
| `sqlcmd: command not found` (exit 127) | Not pre-installed on ubuntu-24.04 | Install `mssql-tools18` via Microsoft apt repo |
| `gpg: cannot open /dev/tty` | `gpg --dearmor` without `--batch` in CI | Use `gpg --batch --yes --dearmor \| sudo tee` |
| OIDC fails `AADSTS70021` | Federated credential subject mismatch | Must match `repo:owner/repo:ref:refs/heads/branch` exactly |
| `AZURE_CREDENTIALS` auth fails silently | `WARNING:` text prepended to SP JSON | Strip with `2>/dev/null \| python3` pipeline |
| Bicep runs on every push (slow) | No change detection | Add `git diff` check, conditional steps |
| `error TS7016: no declaration for 'mssql'` | `@types/mssql` missing | Add `@types/mssql` matching the mssql major |
| New function returns 404 after deploy | Not imported in `api/src/index.ts` | Add `import './functions/{name}'` |
| Functions return 500 on first request | SQL serverless auto-paused | Wait 30–60s, retry |
| Placeholder strings cause cryptic errors | Non-empty placeholders fool `if (!value)` | Use `""` in example files |
| `az functionapp create` creates wrong plan | CLI silently falls back to Y1/Dynamic | Use ARM REST API or Bicep for FC1 |
| `az appservice plan create --sku FC1` fails | CLI doesn't support FC1 reliably | Use ARM REST API |
| ARM PUT doesn't change hosting plan | Can't migrate existing app | Delete and recreate |
| `FUNCTIONS_WORKER_RUNTIME` causes failure | Forbidden on FC1 | Remove from app settings |
| `az functionapp cors add` returns Bad Request | CLI CORS broken on FC1 | Use ARM REST API |
| `"main": "dist/functions/*.js"` doesn't work | Glob not resolved | Use `"main": "dist/index.js"` |
| Missing `package-lock.json` breaks CI | `cache-dependency-path` points to missing file | Commit lock file |
| Publish profile auth 401 on FC1 | Kudu auth different on FC1 | OIDC `azure/login@v3` + `az functionapp deployment source config-zip` |
| `Azure/functions-action` step fails "repository disabled/not found" | Marketplace action outage (June 2026) | Deploy with `az functionapp deployment source config-zip` (#46) |
| Kudu "management operation and deployment operation in quick succession" | Config write/restart right before zip deploy | Config → `sleep 30` → deploy → restart (#47) |
| Functions missing after first zip deploy | v4 host doesn't discover from fresh zip until recycled | `az functionapp restart` after deploy (#48) |
| 503 "Service not configured" after infra deploy | Bicep reset app settings; restore step skipped | Restore in an `always()` job after infra (#49) |
| Cold start 15-30s on ACA | Large Docker image | Use Alpine, prune devDeps |
| SSE connections drop after 4 min | Default 240s request timeout | `--request-timeout 1800` |
| `az containerapp update` has no effect | Unchanged secret values skip restart | `az containerapp revision restart` |
| Secrets not available in app | Env var not linked | `--set-env-vars "VAR=secretref:secret-name"` |
| Docker Hub image not pulled | Rate limit (100/6h anonymous) | Authenticated pulls or move to GHCR/ACR |
| Sidecar / public image broke with no code change | `:latest` tag drifted | Pin by tag or digest (#38) |
| `az acr build` "registry could not be found" | `AcrPush` lacks ARM read, or cross-sub without `--subscription` | Contributor scoped to the registry; pass `--subscription` (#50) |
| Container App bills 24/7 at `minReplicas: 0`, replicas stuck at 1 | Wake vectors / `cooldownPeriod` / CI resurrection / `Activating` on ImagePullFailure | `check-live-replicas.sh`, then gotchas #41–#43, #51 |
| `--replica-retry-limit 0` ignored | CLI treats 0 as falsy | `az rest` PATCH + read back (#52) |
| Job started from code has no env / exits non-zero | `/start` body replaces env; `{template:…}` wrapper is silently empty | Clone container spec, append, POST top-level template (#53) |
| `DeploymentModelNotSupported` (Azure OpenAI) | Model version not available in region | Verify: `az cognitiveservices model list --location ...` |
| `EMAIL_FROM` unknown before first deploy | Azure-managed domain hash auto-generated | Retrieve post-deploy with `az communication email domain show` |
| Email send crashes HTTP handler | `pollUntilDone()` throws | Use `safeSend()` wrapper |
| ACS resources fail with location error | `Microsoft.Communication/*` requires `location: 'global'` | Hardcode `location: 'global'` |
| ACS `dataLocation` fails | Uses plain English, not region IDs | `dataLocation: 'Australia'` |
| ACS circular dependency | `linkedDomains` + `dependsOn` conflict | Declare order: emailService → domain → acs |
| 403 on `roleAssignments` | OIDC SP only has Contributor | Grant `User Access Administrator` at RG scope |
| `listSecrets` output warning | Bicep linter flags secrets in outputs | `#disable-next-line outputs-should-not-contain-secrets` |
| SWA self-referencing URL needed | `APP_BASE_URL` unknown before first deploy | Use `'https://${swa.properties.defaultHostname}'` |
| Can't test before Azure provisioned | No mock pattern | Check `if (!process.env.KEY)` → return mock |
| `local.settings.json` placeholder strings | Fake strings are truthy | Use `""` for all user-input values |
| Bearer auth 401s only behind SWA `/api/*` | SWA edge overwrites `Authorization` | Custom header such as `x-api-key` (#54) |
| `gh workflow run` fails OIDC `AADSTS70021` | Dispatched from the wrong branch | `--ref test` / `--ref production` + a branch guard (#55) |
| SQL Server 2025 container crashes on Apple Silicon | RTM needs AVX; Docker Desktop emulation lacks it | Use `2022-latest` + Rosetta, or 2025 CU1+ (#56) |
| ACS `beginSend()` usage unclear | Async poller API | `beginSend()` → `pollUntilDone()` in `safeSend()` (#35) |
| SQL Serverless bill higher than expected; DB never pauses | Health endpoint or scheduler polls the DB, keeping it awake 24/7 | DB-free shallow health check; or switch to flat Basic tier (~$5/mo). See cost-guardrails Guardrail #11 |

For the full catalogue with explanations, see [references/gotchas.md](references/gotchas.md).

## When to delegate to Microsoft's `azure-diagnostics`

This skill is a **static** catalogue — known failure modes with known fixes. For dynamic failures, delegate:

| Symptom | Use Microsoft's skill |
|---------|----------------------|
| "My deployed app returns 500 — what's in the logs?" | `azure-diagnostics` + Azure MCP for live log queries |
| "Performance is slow — what's the bottleneck?" | `azure-diagnostics` + `appinsights-instrumentation` |
| "What's running in my subscription right now?" | `azure-resource-lookup` |
| "Why is this resource costing so much?" | `azure-cost` |

See [composition-with-azure-diagnostics.md](references/composition-with-azure-diagnostics.md).

## General rules

1. Template + architecture must stay in sync — when behaviour changes, update the templates in the same commit.
2. Always add `@types/*` for packages that don't bundle their own `.d.ts` files.
3. GPG in CI always needs `--batch --yes` and pipe through `sudo tee`.
4. Verify Azure OpenAI / Cognitive model versions per region before writing Bicep.
5. Every new SWA function must be imported in `index.ts` — compilation and deployment alone are insufficient.
6. ACS resources are always `location: 'global'` regardless of where the RG is.
7. Email failures should log, not crash — use `safeSend()` wrapper.
8. Conditional Bicep saves 3–5 min per code-only deploy.
9. Pin sidecar / public images by version — `:latest` drifts and breaks silently.
10. After updating a Container App secret, force a revision restart.
11. No third-party marketplace action in the deploy path when `az` can do the job.
12. `200 OK` proves the app is up, not that this build is live — stamp and assert a build id.
13. Verify a scale-to-zero deploy by image tag, never by curling a URL.

## Composes with

- [curating-azure-deployment-learnings](../curating-azure-deployment-learnings/SKILL.md) — capture new gotchas as you find them
- Microsoft's `azure-diagnostics` — live log/metric queries
- Microsoft's `appinsights-instrumentation` — adding telemetry to a running app
- Microsoft's `azure-resource-lookup` — "what's actually deployed"
