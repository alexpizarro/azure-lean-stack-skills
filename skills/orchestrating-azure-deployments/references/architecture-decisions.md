# Architecture decisions

Non-negotiable defaults that every scaffolded project inherits. These exist because each one has been re-decided multiple times and the current choice is the lowest-cost, lowest-surprise option.

## 1. SWA managed functions by default

`api/` ships inside the same Static Web App deploy as the React frontend. No separate Function App. Free tier covers most workloads.

**When to break this:** timer triggers, queue triggers, AI workloads, anything that needs >30s execution. See [deploying-fc1-flex-consumption-functions](../../deploying-fc1-flex-consumption-functions/SKILL.md).

## 2. SQL Serverless

`GP_S_Gen5_1` SKU, auto-pauses after 15 minutes idle, 0.5 vCores minimum, 1 GB max size, locally-redundant backup.

- First request after pause: 30–60 s cold start
- Cost when paused: storage only (~$0.10/GB/month for the 1GB cap)
- Cost when active: ~$0.52/vCore-hour

**When to break this:** sustained traffic where pause latency hurts UX. Switch to GP/Provisioned with a fixed vCore count.

## 3. OIDC auth (no client secrets)

Two service principals: one for `test` branch, one for `production` branch. Each has a federated credential bound to its branch's `refs/heads/{branch}` subject. No secrets to rotate.

The federated credential subject MUST match `repo:{org}/{repo}:ref:refs/heads/{branch}` exactly — any drift causes `AADSTS70021`.

## 4. JSON parameter files (`.parameters.json` not `.bicepparam`)

`.bicepparam` doesn't accept inline `--parameters key=value` overrides, which the CI workflow needs to inject the SQL admin password from a GitHub secret without writing it to disk.

```bash
az deployment sub create \
  --parameters @infra/environments/test.parameters.json \
  --parameters sqlAdminPassword="$SQL_PASSWORD"
```

## 5. SWA location is `eastasia`

`Microsoft.Web/staticSites` is not supported in `australiaeast`. Supported regions: `westus2`, `centralus`, `eastus2`, `westeurope`, `eastasia`. We default to `eastasia` for proximity to AU users; everything else (RG, SQL, Storage, ACA) uses `australiaeast`.

This is hard-coded in `main.bicep` as `var swaLocation = 'eastasia'` — not a parameter, because changing it has no upside.

## 6. Naming formula `{org}-{project}-{component}-{env}`

Single source of truth: `infra/environments/{env}.parameters.json`. Set `org` and `project` once; every resource name cascades.

| Resource | Name |
|----------|------|
| Resource Group | `{org}-{project}-rg-{env}` |
| Static Web App | `{org}-{project}-swa-{env}` |
| SQL Server | `{org}-{project}-sql-{env}` |
| SQL Database | `{org}-{project}-sqldb-{env}` |
| Storage account | `{org}{project}store{env}` (no hyphens, ≤24 chars) |
| Container App | `{org}-{project}-aca-{env}` |
| GitHub SP | `{org}-{project}-github-{env}` |

## 7. Idempotent everything

- Bicep modules must be safe to re-apply
- SQL migrations from `002` onward use the `__MigrationHistory` guard
- Seed data uses `IF NOT EXISTS` or `MERGE`
- Storage lifecycle rules and ACA scale rules are declarative

## 8. Secrets never in code

- SQL admin password: GitHub secret → injected at deploy time, never in param files
- ACS connection strings, AI keys, etc: retrieved at deploy or set via `az containerapp secret set`
- `local.settings.json.example` uses `""` for all user-input values + `__HINT_*` keys (real placeholders are truthy and break `if (!value)` checks)

## 9. Branch → environment mapping

| Branch | Deploys to | Notes |
|--------|------------|-------|
| `main` | nothing | local dev only |
| `test` | test resource group | triggers `deploy-test.yml` |
| `production` | prod resource group | triggers `deploy-prod.yml` |

Never commit directly to `test` or `production`. Always `git merge main` + push.
