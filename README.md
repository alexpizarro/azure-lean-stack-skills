# Azure Lean Stack

**Azure apps that cost nothing when nobody's using them.**

A Claude Code skill pack for building React + Azure Functions + SQL web apps the lean way — scale-to-zero defaults, branch-per-environment CI/CD, and 37+ documented gotchas so Claude Code can actually deploy to Azure on the first try.

---

## Quick start

**Prerequisites:** [Claude Code](https://code.claude.com), [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login` done), [GitHub CLI](https://cli.github.com/) (`gh auth login` done), Node.js 22.

```bash
# 1. Install the plugin
claude plugin install alexpizarro/azure-lean-stack-skills

# 2. Open an empty directory for your new project
mkdir my-azure-app && cd my-azure-app && claude

# 3. Ask Claude to scaffold:
#    "Scaffold a new Azure web app. Org: acme. Project: taskapp. GitHub: acme/taskapp."

# 4. After files are generated, ask Claude to set up CI/CD:
#    "Set up Azure OIDC and GitHub secrets for this repo."

# 5. Push to the test branch — first deploy in ~5 minutes
git push origin test
```

That's it. Idle cost: ~$0. Light-traffic cost: ~$5/month. Full cost table below.

> **Pin to a specific version** for stable installs across the v2 → v3 jump:
> `claude plugin install alexpizarro/azure-lean-stack-skills@v2.1.0`

---

## Why this exists

I burned out on vibe coding. Lovable, v0, Bolt — they all let me ship something that *looked* like a real app in an afternoon. The moment I tried to take any of them past PoC, the wheels came off. Bloated bundles. Hardcoded values everywhere. State management nobody could maintain. Dead on arrival as a real-world app.

So I went back to what I knew worked: Microsoft Azure. Static Web Apps, Functions, SQL Serverless. Free tier on everything. The kind of stack you can hand to a client and they can keep running for a few dollars a month.

One problem: Claude Code couldn't deploy it.

Wrong Functions plan (Y1 instead of FC1). Deprecated app settings (`FUNCTIONS_WORKER_RUNTIME` is forbidden on FC1). SWA in the wrong region (`australiaeast` isn't supported — `eastasia` only). `gpg: cannot open /dev/tty` in CI. Forty-seven different ways the Azure CLI silently does the wrong thing.

So I built this skill pack. **Azure Lean Stack.** Every pattern in here is proven in a real production project — no fabricated examples. When Claude Code uses these skills, deployments work.

---

## What you get

```
~$0  idle cost for the whole stack
~$5  monthly cost at light traffic
~14  composable Claude Code skills
~37  documented gotchas with verified fixes
~3   real production projects that prove every pattern
```

**Local → test → prod, one branch per tier** — `main` runs a fully-offline local stack (Docker SQL + Azurite, no Azure cost); push to `test` → test env; push to `production` → prod env. No GitHub Environments to configure, no deploy approvals to set up, no manual `terraform apply` from a laptop.

**Free tier by default** — Static Web Apps Free, SQL Serverless with auto-pause, Container Apps scale-to-zero, Application Insights with daily quota cap, Storage with lifecycle rules. Pay for what you actually use.

**Scale up when you need to** — every default is tunable. When traffic justifies it, flip the parameter file and redeploy.

---

## The stack

| Layer | Default | Cost when idle |
|-------|---------|---------------|
| Frontend | React 19 + Vite 6 on Static Web Apps **Free** | $0 |
| API | Azure Functions v4 (Node 22) — SWA managed functions | $0 |
| Database | Azure SQL Serverless `GP_S_Gen5_1`, auto-pause at 15 min | ~$0.10/mo (1GB cap) |
| Background jobs | Container Apps Jobs with `minReplicas: 0` | $0 |
| Scheduled tasks | Logic Apps Consumption | $0.22/mo at 5-min cadence |
| Email | Azure Communication Services Email | $0 (first 100/day free) |
| Observability | Application Insights with `dailyQuotaGb: 1` | <$2/mo |
| Storage | Blob `Standard_LRS` + lifecycle rules (Hot→Cool@60d→Cold@180d) | ~$0.02/GB/mo |
| CI/CD | GitHub Actions with OIDC (no client secrets) | $0 |

A typical low-traffic prototype runs at **under $5/month total**.

---

## What Claude does under the hood

When you ask Claude to scaffold a new app, it routes through these sub-skills in order:

1. [`scaffolding-azure-bicep-infrastructure`](skills/scaffolding-azure-bicep-infrastructure/SKILL.md) — generates `infra/`, `.github/workflows/`, parameter files
2. [`configuring-azure-oidc-for-github-actions`](skills/configuring-azure-oidc-for-github-actions/SKILL.md) — creates service principals + federated credentials + GitHub secrets
3. [`managing-azure-sql-migrations`](skills/managing-azure-sql-migrations/SKILL.md) — sets up the migration system
4. [`deploying-azure-static-web-apps`](skills/deploying-azure-static-web-apps/SKILL.md) — generates the React + Functions code
5. [`applying-azure-cost-guardrails`](skills/applying-azure-cost-guardrails/SKILL.md) — audits the Bicep for cost regressions before first deploy

You don't have to invoke these by name. Describe what you want — *"scaffold an Azure app with SQL and storage"*, *"set up OIDC"*, *"add a recurring scheduler"* — and Claude picks the right sub-skill via [`orchestrating-azure-deployments`](skills/orchestrating-azure-deployments/SKILL.md).

---

## Deploy workflow

Always the same three commands:

```bash
# Deploy to test
git checkout test && git merge main -m "Promote to test: <summary>" && git push origin test

# Deploy to production
git checkout production && git merge test -m "Release to prod: <summary>" && git push origin production

# Back to local dev
git checkout main
```

`main` is never connected to an Azure environment. It exists for local dev only.

Need a new isolated environment? `git checkout -b acme-demo`, set up one OIDC federated credential bound to the branch, push. You have a fully isolated Azure environment in 10 minutes.

---

## The 16 skills

| Skill | When Claude uses it |
|-------|--------------------|
| [`orchestrating-azure-deployments`](skills/orchestrating-azure-deployments/SKILL.md) | The router — picks the right sub-skill for any Azure task |
| [`scaffolding-azure-bicep-infrastructure`](skills/scaffolding-azure-bicep-infrastructure/SKILL.md) | New project, generating `infra/` and workflows |
| [`configuring-azure-oidc-for-github-actions`](skills/configuring-azure-oidc-for-github-actions/SKILL.md) | Service principals, federated credentials, GitHub secrets |
| [`managing-azure-sql-migrations`](skills/managing-azure-sql-migrations/SKILL.md) | Idempotent SQL migrations run via `sqlcmd` in CI |
| [`deploying-azure-static-web-apps`](skills/deploying-azure-static-web-apps/SKILL.md) | SWA + managed functions code conventions |
| [`deploying-fc1-flex-consumption-functions`](skills/deploying-fc1-flex-consumption-functions/SKILL.md) | Timer/queue/AI workloads on standalone Function Apps |
| [`deploying-azure-container-apps`](skills/deploying-azure-container-apps/SKILL.md) | Long-running servers, Jobs, sidecars, multi-app envs |
| [`scheduling-with-azure-logic-apps-consumption`](skills/scheduling-with-azure-logic-apps-consumption/SKILL.md) | Recurring HTTP triggers and lightweight Power-Automate-style flows |
| [`developing-azure-apps-locally`](skills/developing-azure-apps-locally/SKILL.md) | Fully-offline local stack (Docker SQL + Azurite) — the `main`-branch "try" tier |
| [`optimizing-azure-blob-storage-cost`](skills/optimizing-azure-blob-storage-cost/SKILL.md) | Lifecycle rules, CORS for SAS+Range, tier ageing |
| [`adding-azure-communication-services-email`](skills/adding-azure-communication-services-email/SKILL.md) | Transactional email (100/day free) |
| [`instrumenting-azure-app-insights`](skills/instrumenting-azure-app-insights/SKILL.md) | Workspace-based App Insights with daily cap + alerts |
| [`scaffolding-multi-tenant-azure-apps`](skills/scaffolding-multi-tenant-azure-apps/SKILL.md) | One RG per tenant on a shared subscription |
| [`applying-azure-cost-guardrails`](skills/applying-azure-cost-guardrails/SKILL.md) | Consumption-first defaults + a Bicep auditor script |
| [`diagnosing-azure-deployment-failures`](skills/diagnosing-azure-deployment-failures/SKILL.md) | 37+ gotcha catalogue with verified fixes |
| [`curating-azure-deployment-learnings`](skills/curating-azure-deployment-learnings/SKILL.md) | Captures field learnings and promotes recurring ones to gotchas |

See [`RECIPES.md`](RECIPES.md) for working patterns lifted from real projects.

---

## Branch-per-environment — the deployment model

This is the single most important pattern in the pack. **One branch in your repo = one tier.** The flow is **local (`main`) → `test` → `production`.**

```
main         → the local "try" tier — fully-offline Docker stack (SQL + Azurite), no Azure
test         → deploys to {org}-{project}-rg-test
production   → deploys to {org}-{project}-rg-prod
acme-demo    → deploys to {org}-{project}-rg-acme-demo
```

You iterate on `main` against a real local SQL + blob stack (see [`developing-azure-apps-locally`](skills/developing-azure-apps-locally/SKILL.md)), then promote to `test`, then `production`.

Why this works:
- **Branch state IS environment state.** Always. The branch is the source of truth for what's running.
- **OIDC federated credential subject is `repo:owner/repo:ref:refs/heads/{branch}`** — Azure literally won't authenticate a workflow run from the wrong branch. Test SPs cannot deploy to prod, even if a workflow tries.
- **No GitHub Environments to configure.** No deploy approvals. No protected-branches dance.
- **New environment = new branch.** 10 minutes from "we need a demo for next Tuesday" to "here's the URL."

[`configuring-azure-oidc-for-github-actions`](skills/configuring-azure-oidc-for-github-actions/SKILL.md) automates the SP + federated-credential setup for any new branch.

---

## How this complements Microsoft's Azure Skills plugin

Microsoft published their official [Azure Skills plugin](https://github.com/microsoft/azure-skills) with 25 skills + 200+ MCP tools. They cover the live Azure surface — querying resources, running cost analysis, doing RBAC audits.

This pack complements that with opinionated, proven patterns:

| | Microsoft's Azure Skills | Azure Lean Stack (this) |
|---|---|---|
| Scope | All of Azure, generically | The lean-cost SWA + Functions + SQL + ACA stack |
| Strength | Live data via Azure MCP | Battle-tested CI/CD + gotcha catalogue |
| Best for | "What's running in my subscription?" | "Why did my deploy fail?" / "How do I keep this under $5/month?" |
| Installation | `microsoft/azure-skills` | `alexpizarro/azure-lean-stack-skills` |

Install both. Claude Code uses Microsoft's for live diagnostics; Azure Lean Stack for the deployment patterns that aren't in Microsoft's official surface.

---

## Architecture decisions (non-negotiable)

1. **Branch-per-environment.** `main` = dev only; `test` and `production` (and any other branch) map 1:1 to Azure resource groups via branch-scoped OIDC.
2. **SWA managed functions by default.** Free tier. HTTP only. Switch to FC1 only when you need timer/queue/AI triggers.
3. **SQL Serverless.** `GP_S_Gen5_1`, auto-pauses at 15 min idle.
4. **OIDC auth.** Never a client secret in CI.
5. **JSON parameter files.** `.parameters.json` not `.bicepparam` (needs inline `--parameters` overrides).
6. **SWA location is `eastasia`.** Hard-coded; `australiaeast` doesn't support `Microsoft.Web/staticSites`.
7. **Every pattern is proven in a real project.** Nothing in this pack is fabricated — if no shipping project uses it, it doesn't get added.

---

## Production readiness — known gaps

Azure Lean Stack is consumption-priced and optimised for fast iteration. For real production workloads, address these:

| Priority | Gap | Upgrade path |
|----------|-----|-------------|
| 1 | No authentication | Entra ID on SWA, or APIM with JWT validation |
| 2 | SQL password auth | Managed Identity with `db_datareader`/`db_datawriter` |
| 3 | Over-scoped SPs | Scope from subscription to resource group |
| 4 | Public SQL access | Private endpoint + VNet integration |
| 5 | No observability by default | Set `deployObservability: true` (skill: `instrumenting-azure-app-insights`) |
| 6 | SQL cold starts on idle | Upgrade from serverless to provisioned tier |
| 7 | No WAF | Azure Front Door + WAF policy |

---

## Contributing

The skill pack grows from real field experience. The workflow:

1. Hit a problem deploying a real Azure project
2. Capture it via [`curating-azure-deployment-learnings`](skills/curating-azure-deployment-learnings/SKILL.md): `bash skills/curating-azure-deployment-learnings/scripts/capture-learning.sh`
3. When the same problem appears in 2+ projects (or is high-severity), promote it: `bash .../promote-to-gotchas.sh <tag>`
4. PR with the updated gotcha + the Bicep/script change

**No fabricated patterns.** Every skill in this pack must be proven in at least one shipping project. If you want to add a new skill, link to the project that already uses it.

---

## License

MIT — use it, fork it, ship clients on it.
