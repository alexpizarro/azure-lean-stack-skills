# Azure Starter — Claude Code Plugin

A Claude Code plugin that scaffolds and deploys React + Azure Functions + SQL web apps with one `git push`. Every Azure deployment gotcha from 4 real projects — documented and automated.

**Stack:** React 19 + TypeScript | Azure Functions v4 (Node 22) | Azure SQL Serverless | Bicep IaC | GitHub Actions OIDC

---

## Install

```bash
claude plugin install alexpizarro/claude-azure-app-starter
```

Or add to your project's `.claude/settings.json`:

```json
{
  "plugins": ["alexpizarro/claude-azure-app-starter"]
}
```

---

## Usage

```bash
/azure-starter scaffold    # Generate a new project from battle-tested patterns
/azure-starter setup       # Configure Azure OIDC, service principals, GitHub secrets
/azure-starter deploy      # Merge and push to trigger deployment
/azure-starter troubleshoot # Diagnose deployment failures (37 documented gotchas)
/azure-starter upgrade     # Add FC1 Function App, Container Apps, or ACS Email
```

### Scaffold a new project

Open Claude Code in an empty folder:

```
/azure-starter scaffold

org: acme
project: taskapp
repo: acme/taskapp
build: a task manager with CRUD API and user-facing list view
```

Generates all files: React frontend, Azure Functions API, Bicep infrastructure, GitHub Actions workflows, SQL migrations, and a project-specific CLAUDE.md.

### Setup Azure + GitHub

```
/azure-starter setup
```

Claude runs `az` and `gh` commands directly — creates service principals, configures OIDC federated credentials, generates SQL passwords, and sets GitHub secrets. Only asks for values it can't determine from context (subscription ID, org name).

### Deploy

```
/azure-starter deploy
```

Merges to the target branch and pushes. GitHub Actions runs: deploy infrastructure (Bicep) -> run SQL migrations -> build and deploy app.

### Troubleshoot

```
/azure-starter troubleshoot
```

Diagnoses common failures against 37 documented gotchas across Bicep, CI/CD, Azure Functions, FC1, Container Apps, Azure AI, ACS Email, and local development.

---

## What's inside

### The template

A deployable full-stack Azure web app in `template/`:

```
template/
├── .github/workflows/     # CI/CD: deploy-test.yml, deploy-prod.yml
├── infra/                  # Bicep IaC: SWA, SQL Server, resource groups
│   ├── modules/            # resourceGroup, staticWebApp, sqlServer, functionApp
│   ├── environments/       # test.parameters.json, prod.parameters.json
│   └── sql/migrations/     # Versioned, idempotent SQL migrations
├── frontend/               # React 19 + TypeScript + Vite 6
└── api/                    # Azure Functions v4 + Node 22 + TypeScript
```

### The knowledge

Battle-tested deployment patterns in `skills/azure-starter/references/`:

| Reference | What it covers |
|-----------|---------------|
| `scaffold-patterns.md` | Naming conventions, package versions, project structure, API patterns |
| `deployment-setup.md` | OIDC setup, service principals, federated credentials, GitHub secrets |
| `sql-migrations.md` | Migration tracking, guard clauses, idempotent DDL |
| `fc1-guide.md` | Flex Consumption gotchas (CLI silently fails, FUNCTIONS_WORKER_RUNTIME forbidden) |
| `container-apps.md` | Docker scale-to-zero, secretref pattern, SSE timeout |
| `gotchas.md` | 37 deployment issues with verified fixes |

---

## How this relates to Microsoft's Azure Skills plugin

Microsoft published their [Azure Skills plugin](https://github.com/microsoft/azure-skills) (March 2026) with 25 skills and 200+ MCP tools covering `azure-prepare`, `azure-validate`, `azure-deploy` broadly.

**This plugin is complementary, not competing:**

| | Microsoft Azure Skills | This plugin |
|---|---|---|
| Scope | General Azure (200+ tools) | SWA + Functions + SQL stack specifically |
| Strength | Broad coverage, official tooling | Battle-tested patterns, gotcha documentation |
| Best for | "How do I create a resource?" | "Why did my deploy fail?" |

Install both. Use Microsoft's plugin for the tools. Use this for the deployment patterns they don't cover.

---

## Architecture decisions

1. **SWA managed functions** — `api/` deploys with SWA. Free tier. HTTP only.
2. **SQL Serverless** — GP_S_Gen5_1, auto-pauses after 15 min. $0 when idle.
3. **OIDC auth** — no client secrets to rotate. Branch-scoped service principals.
4. **JSON parameter files** — `.parameters.json` not `.bicepparam` (allows inline `--parameters key=value`).
5. **SWA in `eastasia`** — `australiaeast` not supported for `Microsoft.Web/staticSites`.

---

## Enterprise readiness

This starter is free-tier-first and optimised for speed over operational maturity. For production workloads, address these gaps:

| Priority | Gap | Upgrade path |
|----------|-----|-------------|
| 1 | No authentication | Add Entra ID on SWA or API Management with JWT |
| 2 | SQL password auth | Switch to Managed Identity (`db_datareader`/`db_datawriter`) |
| 3 | Over-scoped SPs | Scope from subscription to resource group |
| 4 | Public SQL access | Private endpoint + VNet integration |
| 5 | No observability | Add Application Insights via Bicep |
| 6 | SQL cold starts | Upgrade from serverless to provisioned tier |
| 7 | No WAF | Azure Front Door + WAF policy |
| 8 | No tests | Vitest (frontend) + Jest (API) |

---

## License

MIT
