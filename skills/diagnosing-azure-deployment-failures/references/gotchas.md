# Comprehensive Gotchas Reference

Every deployment issue encountered across real projects, with verified fixes. Add new entries via [curating-azure-deployment-learnings](../../curating-azure-deployment-learnings/SKILL.md).

---

## Bicep & Infrastructure

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 1 | `BCP258: sqlAdminPassword missing` | Using `.bicepparam` instead of `.parameters.json` | Keep params as `.parameters.json`; use `@` prefix: `--parameters @file.json` |
| 2 | `LocationNotAvailableForResourceType` for SWA | `australiaeast` not supported for `Microsoft.Web/staticSites` | `swaLocation` hardcoded to `eastasia` in main.bicep |
| 3 | `listSecrets` output warning | Bicep linter flags secrets in outputs | Suppress: `#disable-next-line outputs-should-not-contain-secrets` |
| 4 | Bicep `roleAssignments` fails with 403 | OIDC SP only has Contributor | Grant `User Access Administrator` at RG scope |
| 5 | ACS resources fail with location error | `Microsoft.Communication/*` requires `location: 'global'` | Hardcode `location: 'global'` on all ACS resources |
| 6 | ACS `dataLocation` fails | Uses plain English, not Azure region IDs | `dataLocation: 'Australia'` not `'australiaeast'` |
| 7 | ACS circular dependency | `linkedDomains` + `dependsOn` conflict | Declare order: emailService → domain → acs. No `dependsOn`. |
| 8 | SWA self-referencing URL needed | `APP_BASE_URL` unknown before first deploy | Use `'https://${swa.properties.defaultHostname}'` in Bicep |

---

## CI/CD Pipeline

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 9 | `Multiple files found matching pattern *.sql` | `azure/sql-action@v2.3` accepts only one file | Replace with `sqlcmd` bash loop (see managing-azure-sql-migrations) |
| 10 | `sqlcmd: No such file` (exit 127) | Not pre-installed on ubuntu-24.04 | Install `mssql-tools18` explicitly via Microsoft apt repo |
| 11 | `gpg: cannot open /dev/tty` | `gpg --dearmor` without `--batch` in headless CI | Use `gpg --batch --yes --dearmor \| sudo tee` |
| 12 | OIDC login fails `AADSTS70021` | Federated credential subject mismatch | Must match `repo:owner/repo:ref:refs/heads/branch` exactly |
| 13 | `AZURE_CREDENTIALS` auth fails silently | `WARNING:` text prepended to SP JSON | Strip with `2>/dev/null \| python3` pipeline |
| 14 | Bicep runs on every push (3-5 min wasted) | No change detection | Add `git diff` check, conditional steps, fallback SWA token |

---

## Azure Functions (SWA Managed)

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 15 | `error TS7016: no declaration for 'mssql'` | `@types/mssql` missing from devDependencies | Add `"@types/mssql": "^9.1.5"` |
| 16 | New function returns 404 after deploy | Not imported in `api/src/index.ts` | Add `import './functions/{name}'` — imports register routes |
| 17 | Functions return 500 on first request | SQL serverless auto-paused | Wait 30-60s, retry — database is resuming |
| 18 | Placeholder strings cause cryptic errors | Non-empty placeholders fool `if (!value)` | Use `""` in example files + `__HINT_*` keys |

---

## FC1 Flex Consumption

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 19 | `az functionapp create` creates wrong plan | CLI silently falls back to Y1/Dynamic | Use ARM REST API or Bicep |
| 20 | `az appservice plan create --sku FC1` fails | CLI doesn't support FC1 reliably | Use ARM REST API |
| 21 | ARM PUT doesn't change hosting plan | Can't migrate existing app | Delete and recreate the app |
| 22 | `FUNCTIONS_WORKER_RUNTIME` causes failure | Forbidden on FC1 | Remove from app settings; runtime in `functionAppConfig` |
| 23 | `az functionapp cors add` returns Bad Request | CLI CORS broken on FC1 | Use ARM REST API for CORS |
| 24 | `"main": "dist/functions/*.js"` doesn't work | Glob patterns not resolved | Use concrete path: `"main": "dist/index.js"` |
| 25 | Missing `package-lock.json` breaks CI | `cache-dependency-path` points to missing file | Commit lock file |
| 26 | Publish profile auth 401 on FC1 | Kudu auth different on FC1 | Use SP auth with `azure/login@v2` |

---

## Container Apps

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 27 | Cold start 15-30s | Large Docker image | Use Alpine, prune devDeps |
| 28 | SSE connections drop after 4 min | Default 240s request timeout | `--request-timeout 1800` |
| 29 | `az containerapp update` has no effect | Unchanged secret values skip restart | `az containerapp revision restart` |
| 30 | Secrets not available in app | Env var not linked to secret | `--set-env-vars "VAR=secretref:secret-name"` |
| 31 | Docker Hub image not pulled | Rate limit (100 pulls/6h anonymous) | Authenticated pulls, GHCR, or ACR |
| 38 | Sidecar :latest tag drifted and broke app | Implicit dependency on a moving target | Pin sidecar images by version (e.g. `crawl4ai:0.8.6`) |
| 39 | New secret value not picked up by replica | `az containerapp secret set` doesn't restart replicas | Follow with `az containerapp revision restart --revision $LATEST` |

---

## Azure AI / OpenAI

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 32 | `DeploymentModelNotSupported` | Model version not available in region | Verify: `az cognitiveservices model list --location <region>` |

---

## Azure Communication Services (Email)

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 33 | `EMAIL_FROM` unknown before first deploy | Azure-managed domain hash auto-generated | Retrieve after deploy: `az communication email domain show` |
| 34 | Email send crashes HTTP handler | `pollUntilDone()` throws on ACS failure | Use `safeSend()` wrapper that logs but doesn't rethrow |
| 35 | `@azure/communication-email` API confusing | Uses async poller, not simple `send()` | `beginSend()` → `pollUntilDone()` pattern |

---

## Local Development

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 36 | Can't test before Azure provisioned | No mock pattern | Check `if (!process.env.KEY)` → return mock response |
| 37 | `local.settings.json` placeholder strings | Fake strings are truthy | Use `""` for all user-input values |

---

## Cost

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 40 | SQL Serverless bill far higher than expected; DB never auto-pauses | A health/status endpoint or a frequent scheduler queries the DB on every call, resetting the auto-pause timer → DB stays awake, billing compute 24/7 | Make the shallow health check DB-free (return 200 without a query; gate any DB check behind `?deep=1`); point schedulers at DB-free endpoints; if access is genuinely steady, switch serverless → flat Basic tier (~$5/mo). Detect with `applying-azure-cost-guardrails/scripts/audit-cost-antipatterns.sh`. See cost-guardrails Guardrail #11. |

---

## General rules

1. **Template and architecture must stay in sync.** When the canonical template changes, update the sub-skill docs in the same commit.
2. **Always add `@types/*`** for packages that don't bundle their own `.d.ts` files.
3. **GPG in CI always needs `--batch --yes`** and pipe through `sudo tee`.
4. **Verify model versions per region** before writing Bicep.
5. **Every new SWA function must be imported in `index.ts`** — compilation and deployment alone are insufficient.
6. **ACS resources are always `location: 'global'`** regardless of where the RG is.
7. **Email failures should log, not crash** — use `safeSend()` wrapper for transactional emails.
8. **Conditional Bicep** saves 3-5 min per code-only deploy.
9. **Pin sidecar / public images by version** — `:latest` will drift and break silently.
10. **After updating a Container App secret, force a revision restart** to pick up the new value.
