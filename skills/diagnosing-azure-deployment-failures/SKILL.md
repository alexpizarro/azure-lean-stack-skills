---
name: diagnosing-azure-deployment-failures
description: Diagnoses Azure deployment failures against a catalogue of 37+ documented gotchas drawn from real projects — Bicep errors (BCP258, LocationNotAvailable), CI/CD failures (AADSTS70021, sqlcmd not found, gpg cannot open /dev/tty), Function App quirks (silent CLI fallback to wrong plan, FUNCTIONS_WORKER_RUNTIME forbidden on FC1), Container Apps issues (SSE drops at 4 min, secret not picked up without revision restart), ACS Email Bicep traps, and SQL serverless cold-start. For live diagnostics of a running app, delegates to Microsoft's azure-diagnostics + appinsights-instrumentation. Use when a deploy fails, a deployed app misbehaves, or a CI step errors.
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
| `error TS7016: no declaration for 'mssql'` | `@types/mssql` missing | Add `"@types/mssql": "^9.1.5"` |
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
| Publish profile auth 401 on FC1 | Kudu auth different on FC1 | Use SP auth with `azure/login@v2` |
| Cold start 15-30s on ACA | Large Docker image | Use Alpine, prune devDeps |
| SSE connections drop after 4 min | Default 240s request timeout | `--request-timeout 1800` |
| `az containerapp update` has no effect | Unchanged secret values skip restart | `az containerapp revision restart` |
| Secrets not available in app | Env var not linked | `--set-env-vars "VAR=secretref:secret-name"` |
| Docker Hub image not pulled | Rate limit (100/6h anonymous) | Authenticated pulls or move to GHCR/ACR |
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

## Composes with

- [curating-azure-deployment-learnings](../curating-azure-deployment-learnings/SKILL.md) — capture new gotchas as you find them
- Microsoft's `azure-diagnostics` — live log/metric queries
- Microsoft's `appinsights-instrumentation` — adding telemetry to a running app
- Microsoft's `azure-resource-lookup` — "what's actually deployed"
