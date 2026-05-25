# CLAUDE.md — Azure Lean Stack (v2.2.0)

**Azure apps that cost nothing when nobody's using them.**

A **Claude Code plugin** of composable skills for scaffolding and deploying consumption-priced, low-cost Azure web apps. One thin orchestrator + 14 single-purpose sub-skills + a learnings-feedback loop. Built around **branch-per-environment CI/CD** where each git branch maps 1:1 to an isolated Azure resource group. Complementary to Microsoft's [azure-skills](https://github.com/microsoft/azure-skills) plugin.

Every pattern in here is **proven in at least one real production project** (see [RECIPES.md](RECIPES.md)). If no shipping project uses it, it doesn't get added.

---

## Plugin structure

```
.
├── .claude-plugin/
│   └── plugin.json                                # Plugin manifest (v2.0.0)
├── skills/
│   ├── orchestrating-azure-deployments/           # ORCHESTRATOR — routes to sub-skills
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── composition-with-azure-skills.md   # Delegation rules to MS azure-skills
│   │       ├── architecture-decisions.md
│   │       └── stack-versions.md
│   │
│   ├── scaffolding-azure-bicep-infrastructure/    # Bicep root, modular toggles, pr-checks.yml
│   ├── configuring-azure-oidc-for-github-actions/ # SPs + federated creds + GH secrets (branch-scoped)
│   ├── managing-azure-sql-migrations/             # Migration system, sqlcmd runner
│   ├── deploying-azure-static-web-apps/           # SWA + managed functions
│   ├── deploying-fc1-flex-consumption-functions/  # FC1 (ARM REST, ESM, MI auth)
│   ├── deploying-azure-container-apps/            # ACA + Jobs + sidecars + shared env
│   ├── scheduling-with-azure-logic-apps-consumption/ # Logic Apps recurring trigger (~$0.22/mo)
│   ├── developing-azure-apps-locally/             # Fully-offline local stack (Docker SQL + Azurite)
│   ├── optimizing-azure-blob-storage-cost/        # Lifecycle rules, CORS, tiers
│   ├── adding-azure-communication-services-email/ # ACS Email + safeSend pattern
│   ├── instrumenting-azure-app-insights/          # Workspace-based AI + dailyCap + alerts
│   ├── scaffolding-multi-tenant-azure-apps/       # One RG per tenant pattern
│   ├── applying-azure-cost-guardrails/            # Consumption-first defaults + audit
│   ├── diagnosing-azure-deployment-failures/      # 37+ gotcha catalogue
│   └── curating-azure-deployment-learnings/       # META: learnings → gotchas pipeline
│       ├── SKILL.md
│       └── scripts/
│           ├── capture-learning.sh
│           ├── review-learnings.sh
│           └── promote-to-gotchas.sh
│
└── learnings/                                     # Staging area (gitignored)
    └── YYYY-MM-DD_{project}.md                   # With frontmatter (project, severity, tags)
```

Each sub-skill owns its own `templates/` (Bicep, workflows, scripts, code) and `references/` (deeper knowledge loaded on demand). No top-level `template/` — every artefact lives next to the skill that owns it.

---

## How it works

Each skill has gerund-form `name:` + a description tuned for discovery. Claude selects skills by description; sub-skills compose freely.

**For a new project**, the orchestrator routes the user through:
1. `scaffolding-azure-bicep-infrastructure` → generates `infra/` + workflows
2. `configuring-azure-oidc-for-github-actions` → SPs + federated creds + secrets
3. `managing-azure-sql-migrations` → migration system + sqlcmd runner
4. `deploying-azure-static-web-apps` → SWA + managed functions code conventions
5. `applying-azure-cost-guardrails` → audit pre-deploy

**For a specific task** (e.g. "add storage lifecycle"), the relevant sub-skill is invoked directly. No need to load the whole stack.

**For diagnostics**, `diagnosing-azure-deployment-failures` matches symptoms against the 37+ gotcha catalogue. If no match, delegate to Microsoft's `azure-diagnostics` for live log/metric queries.

**For learnings**, `curating-azure-deployment-learnings` captures field experience as `learnings/*.md` and promotes recurring patterns into the gotcha catalogue.

---

## Composition with Microsoft's azure-skills

This plugin does **not** rebuild what Microsoft already ships. The orchestrator delegates to:

| Microsoft skill | Used for |
|----------------|----------|
| `azure-resource-lookup` + Azure MCP | Live "what's running in my subscription" queries |
| `azure-cost` | Cost analysis of running deployments |
| `azure-diagnostics` | Live log/metric queries on running apps |
| `appinsights-instrumentation` | Adding telemetry to an existing app |
| `azure-rbac` | RBAC verification on deployed resources |
| `entra-app-registration` | Deeper Entra mechanics |
| `azure-enterprise-infra-planner` | Enterprise-scale planning |

This plugin owns: the opinionated low-cost defaults, the gotcha catalogue (37+ entries), the one-git-push workflows, the consumption-first SKU selection, multi-tenant pattern, and the learnings feedback loop.

---

## Contributing

### Branch strategy

- `main` — all development. Tag `v1.0.0` exists for users pinning to the pre-decomposition plugin.
- Do not create `test` / `production` branches here — those are conventions for **derived** projects.

### Adding / extending a skill

1. Choose the smallest single-purpose scope that covers the new capability.
2. Use gerund-form skill names (e.g. `deploying-x`, `optimizing-y`, `instrumenting-z`).
3. Keep SKILL.md under 500 lines. Push detail into one-level-deep `references/*.md`.
4. Put templates (Bicep, workflows, scripts, code) in the skill's own `templates/` dir.
5. Add a "Composes with" section listing related sub-skills and Microsoft skills.

### Adding a gotcha

1. Capture the field experience first with `curating-azure-deployment-learnings/scripts/capture-learning.sh` — writes a frontmatter-stamped `learnings/YYYY-MM-DD_{project}.md`.
2. Periodically review with `review-learnings.sh` — flags recurring/high-severity entries.
3. Promote with `promote-to-gotchas.sh {tag}` — appends a row to `diagnosing-azure-deployment-failures/references/gotchas.md`.
4. Mark the learning's frontmatter `promoted: true` and update the Status line with the commit SHA.

### Bumping skill defaults

If a stack version, SKU, or pattern changes:
1. Update the relevant sub-skill's `templates/` (single source of truth)
2. Update the sub-skill's SKILL.md / references
3. Update `orchestrating-azure-deployments/references/stack-versions.md` if it's a global version bump
4. Same commit. Don't leave docs and templates out of sync.

---

## Guiding principles

1. **Simple git push > everything else** — if a change makes deployment harder, reconsider it.
2. **Free tier > Consumption > fixed cost** — use the cheapest option that meets the need. `applying-azure-cost-guardrails` codifies this.
3. **Secrets never in code** — SQL password injected at deploy time, never in param files. ACS / API keys via `secretref:`.
4. **Idempotent everything** — Bicep, SQL migrations, seed data must be safe to re-run.
5. **Single-purpose skills** — each skill has one verb, one audience, one trigger surface. Compose, don't bundle.
6. **Document every gotcha** — if you hit a wall, capture it as a learning, then promote it. The next person should find it in the catalogue.
7. **Complement, don't reinvent** — Microsoft owns generic Azure; we own opinionated low-cost.
