# Architecture decisions

Non-negotiable defaults that every scaffolded project inherits. These exist because each one has been re-decided multiple times across real production projects and the current choice is the lowest-cost, lowest-surprise option.

## 0. Branch-per-environment (THE deployment model)

**One branch in the repo = one isolated Azure environment.** This is the most important decision in the pack — every other decision flows from it.

```
main         → not deployed anywhere (local dev only)
test         → deploys to {org}-{project}-rg-test
production   → deploys to {org}-{project}-rg-prod
{any other}  → deploys to {org}-{project}-rg-{branch} (if you set it up)
```

### Why

- **Branch state IS environment state.** Always. The branch is the source of truth for what's running in Azure.
- **OIDC federated credential subject is `repo:{owner}/{repo}:ref:refs/heads/{branch}`** — Azure literally won't authenticate a workflow run whose token doesn't carry that exact branch. Test SPs cannot deploy to prod, even if a workflow tries.
- **Zero environment management.** No GitHub Environments. No deploy approvals. No protected-branches dance. No manual `terraform apply` from a laptop.
- **Trivially repeatable.** New isolated environment = new branch + one SP + one federated credential. Ten minutes end to end.

### How

- `main` is never connected to Azure. Use it for local dev only. Run `npm run dev` against an empty database or a developer's personal Azure resources.
- `test` branch's workflow (`deploy-test.yml`) deploys to `{org}-{project}-rg-test`.
- `production` branch's workflow (`deploy-prod.yml`) deploys to `{org}-{project}-rg-prod`.
- New environments (`acme-demo`, `customer-x-uat`) get their own SP + federated credential via [`configuring-azure-oidc-for-github-actions`](../../configuring-azure-oidc-for-github-actions/SKILL.md).

### Promotion

Deployment is always `merge + push`:

```bash
git checkout test && git merge main -m "Promote to test: <summary>" && git push origin test
git checkout production && git merge test -m "Release to prod: <summary>" && git push origin production
git checkout main
```

Never commit directly to `test` or `production`. The merge message becomes the deployment changelog (`git log --merges` reads as a release history).

### Proven in

- `bc-videohub-lite`
- `trg-directory-website`
- `trg-directory-content-crawl`

All three use exactly this pattern with `deploy-test.yml` + `deploy-prod.yml` workflows.

---

## 1. SWA managed functions by default

`api/` ships inside the same Static Web App deploy as the React frontend. No separate Function App. Free tier covers most workloads.

**When to break this:** timer triggers, queue triggers, AI workloads, anything that needs >30s execution. See [`deploying-fc1-flex-consumption-functions`](../../deploying-fc1-flex-consumption-functions/SKILL.md).

## 2. SQL Serverless

`GP_S_Gen5_1` SKU, auto-pauses after 15 minutes idle, 0.5 vCores minimum, 1 GB max size, locally-redundant backup.

- First request after pause: 30–60 s cold start
- Cost when paused: storage only (~$0.10/GB/month for the 1GB cap)
- Cost when active: ~$0.52/vCore-hour

**When to break this:** sustained traffic where pause latency hurts UX. Switch to GP/Provisioned with a fixed vCore count.

## 3. OIDC auth (no client secrets)

Two service principals per project for `test` and `production` branches; one more for each new environment-branch. Each SP has a federated credential bound to its branch's `refs/heads/{branch}` subject. No secrets to rotate.

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
| Logic App (scheduler) | `{org}-{project}-sched-{env}` |
| GitHub SP | `{org}-{project}-github-{env}` |

## 7. Idempotent everything

- Bicep modules safe to re-apply
- SQL migrations from `002` onward use the `__MigrationHistory` guard
- Seed data uses `IF NOT EXISTS` or `MERGE`
- Storage lifecycle rules and ACA scale rules are declarative

## 8. Secrets never in code

- SQL admin password: GitHub secret → injected at deploy time, never in param files
- ACS connection strings, AI keys, etc: retrieved at deploy or set via `az containerapp secret set`
- `local.settings.json.example` uses `""` for all user-input values + `__HINT_*` keys (real placeholders are truthy and break `if (!value)` checks)

## 9. Every pattern in this pack is proven

If no shipping project uses a pattern, it doesn't get added. The current proven patterns trace to:

- `bc-videohub-lite` — multi-tenant Bicep, Storage lifecycle, ACA Jobs, shared managed env
- `trg-directory-website` — modular toggles, workspace-based App Insights, Container Apps Job for SWA deploys, Logic Apps Consumption scheduler
- `trg-directory-content-crawl` — multi-container ACA with sidecar + probes, Azure OpenAI via Cognitive Services, GHA OIDC for ACA deploys

If you're tempted to add something that isn't yet in a shipping project, capture it as a *learning* via [`curating-azure-deployment-learnings`](../../curating-azure-deployment-learnings/SKILL.md) and promote it once a real project uses it.
