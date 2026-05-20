---
name: orchestrating-azure-deployments
description: Routes Azure web app work (scaffold, deploy, troubleshoot, evolve) to the right Azure Lean Stack sub-skill. Built around branch-per-environment CI/CD where each git branch maps to one isolated Azure resource group via OIDC. Use when building or deploying a new Azure app, setting up GitHub Actions for Azure, troubleshooting a failed deploy, or adding FC1 / Container Apps / Logic Apps / multi-tenant patterns.
---

# Orchestrating Azure Deployments (Azure Lean Stack)

Thin router for Azure app deployments. Holds no domain knowledge of its own — every task is delegated to a single-purpose sub-skill or to Microsoft's `azure-skills` plugin.

**Stack defaults:** React 19 + TypeScript | Azure Functions v4 (Node 22) | Azure SQL Serverless | Bicep IaC | GitHub Actions OIDC | **branch-per-environment**

**Last verified:** May 2026

---

## The deployment model — branch-per-environment

Before delegating anything else, internalise the deployment model. **One branch in the repo = one isolated Azure resource group.** `main` is never connected to Azure — it's for local dev only. `test` → test RG. `production` → prod RG. New branch + one OIDC credential = new isolated environment.

This model is non-negotiable. Every sub-skill assumes it. See [references/architecture-decisions.md](references/architecture-decisions.md) decision #0 for the full rationale (and the OIDC subject lockdown that makes it safe).

---

## How to use this skill

Identify the user's task, then delegate. Never inline domain knowledge from a sub-skill — read the sub-skill's SKILL.md and follow it.

### Routing table

| User intent | Skill to invoke |
|-------------|----------------|
| "Scaffold a new Azure web app" / "set up a new project" | [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) |
| "Set up OIDC" / "configure GitHub Actions for Azure" / "create service principals" | [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md) |
| "Add a SQL migration" / "set up the migration system" | [managing-azure-sql-migrations](../managing-azure-sql-migrations/SKILL.md) |
| "Deploy a React + Functions app" / "SWA" / "Static Web Apps" | [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md) |
| "Add a timer trigger" / "queue trigger" / "AI workload" / "FC1" / "Flex Consumption" | [deploying-fc1-flex-consumption-functions](../deploying-fc1-flex-consumption-functions/SKILL.md) |
| "Docker on Azure" / "Container Apps" / "WebSocket/SSE" / "long-running server" / "background job" | [deploying-azure-container-apps](../deploying-azure-container-apps/SKILL.md) |
| "Blob storage cost" / "lifecycle rules" / "tier to cool/cold" / "delete old blobs" | [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md) |
| "Transactional email" / "ACS email" / "send email from Azure" | [adding-azure-communication-services-email](../adding-azure-communication-services-email/SKILL.md) |
| "Add observability" / "App Insights" / "metric alerts" / "5xx alerts" | [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md) |
| "Multi-tenant" / "one RG per customer" / "per-tenant isolation" | [scaffolding-multi-tenant-azure-apps](../scaffolding-multi-tenant-azure-apps/SKILL.md) |
| "Recurring trigger" / "schedule" / "Logic App" / "Power-Automate-like flow" / "ping every N minutes" | [scheduling-with-azure-logic-apps-consumption](../scheduling-with-azure-logic-apps-consumption/SKILL.md) |
| "Reduce cost" / "audit SKUs" / "stay on free tier" / "consumption-only" | [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) |
| "Deploy failed" / "diagnose this error" / "AADSTS70021" / "BCP258" / "LocationNotAvailable" | [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) |
| "I learned something" / "promote a learning to gotchas" / "capture this lesson" | [curating-azure-deployment-learnings](../curating-azure-deployment-learnings/SKILL.md) |

### When to delegate to Microsoft's azure-skills

This skill is **complementary** to Microsoft's [azure-skills](https://github.com/microsoft/azure-skills) plugin. See [references/composition-with-azure-skills.md](references/composition-with-azure-skills.md) for the full decision tree. Quick rules:

| Task | Use Microsoft skill |
|------|---------------------|
| Live Azure resource lookup ("what's running in my subscription?") | `azure-resource-lookup` + Azure MCP |
| Cost analysis of a running deployment | `azure-cost` |
| App Insights diagnostics on a live app | `azure-diagnostics` + `appinsights-instrumentation` |
| RBAC verification / role assignments | `azure-rbac` |
| Entra app registration mechanics | `entra-app-registration` |
| Enterprise infra planning | `azure-enterprise-infra-planner` |
| Quota / region availability checks | `azure-quotas` |

This skill owns: the opinionated low-cost scaffold, the gotcha catalogue, end-to-end CI/CD workflows, and the learnings-feedback loop.

---

## Architecture decisions (non-negotiable)

Detailed in [references/architecture-decisions.md](references/architecture-decisions.md). Summary:

1. **SWA managed functions by default** — `api/` deploys with SWA. Free tier. HTTP only.
2. **SQL Serverless** — `GP_S_Gen5_1`, auto-pauses after 15 min, 0.5 vCores min, 1 GB max.
3. **OIDC auth** — no client secrets to rotate. Branch-scoped SPs.
4. **JSON parameter files** — `.parameters.json` not `.bicepparam`.
5. **SWA location** — `eastasia` (not `australiaeast`). All other resources use `australiaeast` by default.

For the canonical stack versions (React, Vite, Node, mssql, Bicep), see [references/stack-versions.md](references/stack-versions.md).

---

## Workflow for a new project

When a user wants a complete new Azure app:

1. Read [scaffolding-azure-bicep-infrastructure/SKILL.md](../scaffolding-azure-bicep-infrastructure/SKILL.md) and generate files.
2. Read [configuring-azure-oidc-for-github-actions/SKILL.md](../configuring-azure-oidc-for-github-actions/SKILL.md) and run setup scripts.
3. Read [managing-azure-sql-migrations/SKILL.md](../managing-azure-sql-migrations/SKILL.md) for the migration system.
4. Read [deploying-azure-static-web-apps/SKILL.md](../deploying-azure-static-web-apps/SKILL.md) for SWA specifics.
5. Read [applying-azure-cost-guardrails/SKILL.md](../applying-azure-cost-guardrails/SKILL.md) to verify defaults are consumption-priced.
6. Optionally read [instrumenting-azure-app-insights/SKILL.md](../instrumenting-azure-app-insights/SKILL.md) for observability.

If a deploy then fails, route to [diagnosing-azure-deployment-failures/SKILL.md](../diagnosing-azure-deployment-failures/SKILL.md).

---

## Deploy workflow

Deployment is `merge + push` — always. `main` never deploys anywhere.

```bash
# Deploy to test
git checkout test && git merge main -m "Promote to test: <summary>" && git push origin test

# Deploy to production
git checkout production && git merge test -m "Release to prod: <summary>" && git push origin production

# Return to main (local dev only — no Azure environment attached)
git checkout main
```

Watch progress: `gh run list --limit 4` then `gh run watch <run-id>`.

**Need a new isolated environment?** (Customer demo, UAT, feature branch with its own Azure stack.) Create the branch, run [`configuring-azure-oidc-for-github-actions`](../configuring-azure-oidc-for-github-actions/SKILL.md) with the new branch name, push. Ten minutes end to end.
