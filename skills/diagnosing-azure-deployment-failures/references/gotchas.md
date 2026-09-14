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
| 15 | `error TS7016: no declaration for 'mssql'` | `@types/mssql` missing from devDependencies | Add `@types/mssql` matching the mssql major (`^12.3.0` for mssql 12) |
| 16 | New function returns 404 after deploy | Not imported in `api/src/index.ts` | Add `import './functions/{name}'` — imports register routes |
| 17 | Functions return 500 on first request | SQL serverless auto-paused | Wait 30-60s, retry — database is resuming |
| 18 | Placeholder strings cause cryptic errors | Non-empty placeholders fool `if (!value)` | Use `""` in example files + `__HINT_*` keys |
| 54 | Bearer / API-key auth works locally but 401s behind SWA `/api/*` | The SWA edge **overwrites the `Authorization` header** with its own platform token | Send API keys in a custom header (`x-api-key`); switch callers *before* pointing DNS at the SWA |
| 55 | `gh workflow run deploy-test.yml` fails OIDC with `AADSTS70021` | Dispatched from the wrong ref — federated credentials are branch-scoped | `gh workflow run … --ref test`; add a branch guard step that refuses other refs |

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
| 26 | Publish profile auth 401 on FC1 | Kudu auth different on FC1 | Use OIDC SP auth with `azure/login@v3` + `az functionapp deployment source config-zip` |
| 46 | Every FC1 deploy suddenly fails: `Azure/functions-action` "repository not found / disabled" | The marketplace action's repo was disabled on GitHub 2026-06-05 → 06-10 (third-party single point of failure) | Deploy with `az functionapp deployment source config-zip` + `az functionapp restart` — no marketplace action in the deploy path |
| 47 | Kudu: "Do not perform a management operation and a deployment operation in quick succession" / config-zip aborts with "SCM container restart" | A config write or restart ran immediately before the zip deploy | Config first → `sleep 30` → deploy → restart. Retry `config-zip` once if it still aborts |
| 48 | Functions missing after the first zip deploy to a fresh Function App | v4 Node host doesn't always discover functions from a fresh config-zip until it recycles | `az functionapp restart` after the deploy — makes registration deterministic |
| 49 | API returns 503 "Service not configured" after an infra deploy | Bicep reset the Function App's app settings; the settings-restore step was skipped because a later quality gate failed | Put settings-restore in its own job with `if: always() && needs.deploy-infra.result == 'success'`; keep the auth-mode flags in the restore list |

---

## Container Apps

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 27 | Cold start 15-30s | Large Docker image | Use Alpine, prune devDeps |
| 28 | SSE connections drop after 4 min | Default 240s request timeout | `--request-timeout 1800` |
| 29 | `az containerapp update` has no effect | Unchanged secret values skip restart | `az containerapp revision restart` |
| 30 | Secrets not available in app | Env var not linked to secret | `--set-env-vars "VAR=secretref:secret-name"` |
| 31 | Docker Hub image not pulled | Rate limit (100 pulls/6h anonymous) | Authenticated pulls, GHCR, or ACR |
| 50 | `az acr build` fails "registry … could not be found in subscription" although it exists | The SP has only `AcrPush` (data plane) — no ARM `registries/read`; or the registry lives in another subscription and `--subscription` wasn't passed | Grant **Contributor scoped to the registry resource**; pass `--subscription <acr-sub>` to `az acr login` / `az acr build` (OIDC login only scopes the app's subscription) |
| 51 | Container App bills full vCPU with `minReplicas: 0` and serves nothing; replica stuck `Activating` | `ImagePullFailure` — the registry was deleted / repointed and the app never got a new image (12 days ≈ A$420) | Repoint every consumer *before* deleting a registry; sweep for `Activating` replicas with `check-live-replicas.sh` |
| 52 | `az containerapp job update --replica-retry-limit 0` has no effect | The CLI treats `0` as falsy and keeps `1`, while reporting success | `az rest --method PATCH` the job and read the value back |
| 53 | Job started from code runs with no env vars / exits non-zero | `POST …/jobs/{name}/start` body **replaces** the whole env list, or was wrapped in `{ "template": … }` (silently treated as empty) | GET the job → clone `template.containers[0]` → append vars → POST the top-level `JobExecutionTemplate` |
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
| 41 | Container App bills 24/7 despite `minReplicas: 0`; live replicas stuck at 1 | **Inbound wake vectors** — an *anonymous* health endpoint that probes a downstream service, a status page `setInterval(30s)` (2,880 hits/day **per open tab**, and it keeps polling in a background tab), or a scheduler that wakes the service *before* checking whether the queue is empty | Make downstream probes opt-in (`?probe=x`) **and** authenticated; gate UI polling on `document.visibilityState`; **peek the queue before waking anything**. Use a three-state `healthy: true\|false\|null` so a never-probed service isn't reported as an outage. Guardrail #12a. |
| 42 | Low-traffic Container App never scales to zero; config looks correct | **`cooldownPeriod` > mean inter-arrival time** — each request extends the alive window, so it never closes. `cooldownPeriod: 7200` + 1 request/18 min = pinned 24/7 (measured: ~A$2/day to serve 26 requests per 8 h). Functionally `minReplicas: 1`, but invisible in review | Leave `cooldownPeriod` at the 300s default unless you have measured cause. Treat any value > 300 as an always-on declaration. Guardrail #12b. |
| 43 | A retired/deleted resource keeps coming back and re-incurring cost | **Your own CI resurrects it.** A deploy workflow running `az containerapp update` against it — or `curl`ing its `/health` to "verify the deploy" — recreates and re-wakes it every deploy. (Seen twice; the prod workflow even targeted an already-deleted resource, so the step could only ever fail, unnoticed) | Retirement checklist: deactivate **all** revisions → remove from IaC → **`grep` the CI workflows for the resource name** → add a structural test asserting no workflow references it. Verify the deploy by asserting the *image tag* on the surviving resource, never by curling a URL. Guardrail #13. |
| 44 | "We fixed the cost leak" — but it recurs | Fix was verified from **config**, not billing. Every incident *looks* fixed in config | Prove it per-resource in billing. **`az costmanagement query` does not exist** — POST to `.../providers/Microsoft.CostManagement/query?api-version=2024-08-01` with `granularity: Daily` grouped by `ResourceId`. The last day of a window is partial and reads low — don't call a fix proven off it. Guardrail #14. |
| 45 | Scale-to-zero abandoned because "external ingress can't scale to zero" | **False rule.** Claim: platform health probes hit the ingress ~1/min and count as ingress traffic. Measured against a real estate: **9 of 10 apps** with external ingress, `minReplicas: 0`, no VNet and default cooldown were sitting at **0 replicas** | Reject it. When one app is pinned and its peers aren't, the cause is in that app (gotchas 41–43), not the platform. Acting on the false rule pushes you onto always-on SKUs — the opposite of the fix. |

---

## Local Development (continued)

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 56 | `mcr.microsoft.com/mssql/server:2025-latest` crashes on Apple Silicon (AVX / "illegal instruction") | SQL Server 2025 RTM needs AVX, which Docker Desktop's x86 emulation lacks; CU1+ fixes it | Stay on `2022-latest` with Rosetta for local dev, or use `2025-latest` only after CU1 (OrbStack also works) |

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
11. **No third-party marketplace action in the deploy path** for anything you can do with `az` — `Azure/functions-action` going dark took every dependent pipeline with it.
12. **`200 OK` proves the app is up, not that this build is live.** Stamp a `build-info.json` with the commit SHA into the bundle and assert it after deploy.
13. **Verify a scale-to-zero deploy by image tag, never by curling a URL.**
