# Composition with Microsoft's azure-skills

This skill is **complementary** to [microsoft/azure-skills](https://github.com/microsoft/azure-skills). That plugin ships 25 curated Azure skills + the Azure MCP Server (200+ structured tools) + the Foundry MCP. Install both for the full experience.

## What each plugin owns

**Microsoft's azure-skills** (general Azure expertise + live execution):

| Skill | Use for |
|-------|---------|
| `azure-prepare` | Pre-flight environment checks before any Azure work |
| `azure-validate` | Validating Bicep / configurations before deploy |
| `azure-deploy` | Generic deployment lifecycle (not opinionated) |
| `azure-upgrade` | Resource upgrade workflows |
| `azure-resource-lookup` | Live query: "what's in my subscription?" |
| `azure-quotas` | Region/quota availability checks |
| `azure-cost` | Cost analysis on running deployments |
| `azure-diagnostics` | Live troubleshooting of running resources |
| `appinsights-instrumentation` | Adding telemetry to existing apps |
| `azure-rbac` | Role assignments, permissions audit |
| `entra-app-registration` | App registration / federated credentials mechanics |
| `azure-compliance` | Governance checks |
| `azure-enterprise-infra-planner` | Enterprise-scale planning |
| `azure-messaging`, `azure-storage`, `azure-ai`, `azure-aigateway`, ... | Service-specific Q&A |

**This plugin** (opinionated, low-cost web-app scaffold + battle-tested gotchas):

- The "one git push" workflow templates (`deploy-test.yml`, `deploy-prod.yml`)
- The naming formula `{org}-{project}-{component}-{env}` with single-source-of-truth parameter files
- Pre-tuned consumption defaults: SWA Free + SQL Serverless + ACA scale-to-zero + Storage lifecycle rules
- Cross-cutting gotcha catalogue (SWA `eastasia`, FC1 CLI silent failures, ACS `dataLocation` quirks, GHA conditional Bicep, sqlcmd install on ubuntu-24.04)
- Learnings-feedback loop (`curating-azure-deployment-learnings`)
- Multi-tenant pattern (single tenant param drives RG + names)
- Storage lifecycle rules tuned for media workloads (Hot → Cool@60d → Cold@180d, never Archive)
- Workspace-based App Insights with `dailyQuotaGb` cost cap

## Decision tree

```
User task starts here.
│
├─ "What's running / what's the state right now?"
│  └─ Microsoft: azure-resource-lookup + Azure MCP
│
├─ "How much am I spending?"
│  └─ Microsoft: azure-cost (live data)
│     +
│     This plugin: applying-azure-cost-guardrails (preventive design)
│
├─ "My deployed app is broken."
│  └─ Microsoft: azure-diagnostics (logs, metrics)
│     +
│     This plugin: diagnosing-azure-deployment-failures (gotcha catalogue)
│
├─ "Set up federated credentials / RBAC."
│  └─ Microsoft: entra-app-registration + azure-rbac (general)
│     +
│     This plugin: configuring-azure-oidc-for-github-actions (opinionated 6-secret setup)
│
├─ "Build a new app from scratch."
│  └─ This plugin: orchestrating-azure-deployments → scaffolding-* skills
│
├─ "Deploy / upgrade an existing app."
│  └─ This plugin sub-skills (SWA, FC1, ACA) for our opinionated stack
│     +
│     Microsoft: azure-upgrade for generic upgrade flows
│
└─ "I hit an error — was it documented?"
   └─ This plugin: diagnosing-azure-deployment-failures (37+ entries)
      Falls back to Microsoft: azure-diagnostics for live triage
```

## Practical rules

1. **For live data, prefer Microsoft + Azure MCP.** They have direct API access via the Azure MCP Server's 200+ tools. This skill's scripts only assume `az` CLI is installed and authenticated.
2. **For opinionated defaults, prefer this skill.** Microsoft's plugin is intentionally generic. This one bakes in choices that keep cost low and deployments simple.
3. **For gotchas, check this skill first.** Microsoft's plugin documents the official happy path; this one documents what breaks when you actually deploy.
4. **For new projects, lead with this skill.** Then delegate to Microsoft where they have deeper coverage (e.g. RBAC mechanics).
