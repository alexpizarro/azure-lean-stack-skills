---
name: deploying-azure-container-apps
description: Deploys Docker containers to Azure Container Apps with scale-to-zero that actually scales to zero — cooldownPeriod kept at 300s, KEDA cron warm windows instead of minReplicas 1, Jobs for anything async, and the retirement checklist that stops CI resurrecting a deleted app. Covers multi-container sidecars, shared managed environments, Container Apps Jobs, the az rest PATCH escape hatch for CLI flags that silently no-op, and the job-start env-override trap. Use when SWA + FC1 don't fit — long-running servers, WebSocket/SSE, Next.js with middleware, custom runtimes, scheduled or queue-driven background jobs.
---

# Deploying Azure Container Apps

Scale-to-zero Docker containers for workloads SWA + FC1 can't handle: long-running servers, WebSocket/SSE, streaming, custom runtimes, multi-process sidecars, and run-to-completion background jobs.

## When to use Container Apps

| Need | Use |
|------|-----|
| CRUD API + React frontend | SWA — not this |
| Timer/queue trigger, AI workload, < 30 min | FC1 — not this |
| Long-running HTTP server, > 30s requests | **Container App** (this skill) |
| WebSocket / SSE / streaming | **Container App** with `--request-timeout 1800` |
| Sidecar (e.g. headless browser, embedded DB) | **Container App** multi-container |
| Batch / cron / one-shot processor | **Container Apps Job** (this skill, jobs section) |
| Multiple related apps sharing logs/networking | **Shared managed environment** (this skill) |

## Cost defaults

| State | Cost |
|-------|------|
| Idle (`minReplicas: 0`, `cooldownPeriod: 300`) | $0 |
| Active (template default 0.5 vCPU / 1 GiB) | pennies/month at low traffic |
| Always warm (`minReplicas: 1`, or `cooldownPeriod` longer than your traffic gaps) | ~A$8/day for a 1.5 vCPU replica, ~US$5/mo for the smallest |
| Log Analytics workspace | bound by `dailyQuotaGb` on the workspace (see [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md)) |

**Scale-to-zero is a whole-system property, not a config value.** Four things silently pin a `minReplicas: 0` app at one billed replica 24/7 (gotchas #41–#45): something calling it (your own status page, an anonymous health probe, a scheduler that wakes it *then* checks for work), `cooldownPeriod` longer than the gap between requests, a replica stuck in `Activating` on an `ImagePullFailure` (bills full vCPU — one deleted registry cost A$420/mo for 12 days), and your own CI `curl`ing `/health` or `az containerapp update`-ing a retired app. Check **running replicas**, never revisions: [`applying-azure-cost-guardrails/scripts/check-live-replicas.sh`](../applying-azure-cost-guardrails/scripts/check-live-replicas.sh).

## Warm windows: KEDA `cron`, never a longer cooldown

If users hit the app at a known time (a class night, office hours), pin a replica for that window with a KEDA `cron` scale rule and leave `cooldownPeriod` at 300:

```json
{ "name": "class-night-warm", "custom": { "type": "cron", "metadata": {
    "timezone": "Australia/Sydney", "start": "45 17 * * 2", "end": "30 23 * * 2", "desiredReplicas": "1" } } }
```

KEDA takes `max(rules)`, so HTTP scaling still works inside the window and the app sleeps at 0 outside it; the IANA timezone means DST is handled for you. Non-HTTP rules need `activeRevisionsMode: Single`. The `az containerapp` CLI has no cooldown or cron flags — apply with an ARM merge-PATCH and **always send the complete `rules` array** (a partial PATCH replaces it):

```bash
az rest --method PATCH \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.App/containerapps/$APP?api-version=2025-01-01" \
  --headers "Content-Type=application/json" --body @scale-config.json
az containerapp show -n "$APP" -g "$RG" --query properties.template.scale   # PATCH returns an empty body — read back
```

[templates/scale-config.json](templates/scale-config.json) is the proven shape; `templates/containerApp.bicep` exposes the same thing as `warmWindowStart` / `warmWindowEnd` params. Proven: `bcci-app` (BC Quick Check In) — a `cooldownPeriod: 7200` "to avoid cold starts" cost A$56/mo; the cron rule costs ~A$0.02/day. `az containerapp update --image` (what CI runs) preserves scale rules.

## Critical pattern: share the managed environment

A `Microsoft.App/managedEnvironments` resource is the unit that owns networking + Log Analytics. **One environment can host many Container Apps and Jobs.** Sharing saves Log Analytics workspace cost and simplifies VNet wiring.

```bicep
// One env created once
module env 'modules/managedEnv.bicep' = { ... }

// Multiple apps reuse it
module appA 'modules/containerApp.bicep' = {
  params: { managedEnvironmentId: env.outputs.id, ... }
}
module appB 'modules/containerApp.bicep' = {
  params: { managedEnvironmentId: env.outputs.id, ... }
}
module syncJob 'modules/containerAppJob.bicep' = {
  params: { environmentId: env.outputs.id, ... }
}
```

See [references/multi-app-shared-env.md](references/multi-app-shared-env.md).

## Container Apps Jobs — scale-to-zero by nature

For run-to-completion workloads (batch processing, sync, scheduled crawls), use `Microsoft.App/jobs` instead of a Container App. A Job only runs when triggered; there are no idle replicas — and no ingress, so nothing can wake it by accident. **Prefer a Job for anything async**; the TRG enrichment service moved from an always-on HTTP app to a Job after three idle-burn incidents.

Triggers:
- `Manual` — started via `az containerapp job start` (with optional `--env-vars` for per-run inputs)
- `Schedule` — cron expression
- `Event` — Azure queue/event source

```bicep
resource job 'Microsoft.App/jobs@2025-01-01' = {
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'   // no idle billing
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600                // seconds — max single-run duration
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
    }
    template: { ... }
  }
}
```

Trigger with per-run inputs:

```bash
az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --env-vars "INPUT_ID=$ID" "BLOB_PATH=$PATH"
```

Three traps when driving Jobs from code or CLI (`POST .../jobs/{name}/start`):
- The body **replaces the container's entire env list**. GET the job, clone `template.containers[0]` verbatim, append your vars, then POST — a naive `{ env: [...] }` drops every secretRef-backed setting and the job dies on startup.
- The body is a top-level `JobExecutionTemplate` (`{ "containers": [...], "initContainers": [...] }`). Wrapping it in `{ "template": ... }` is silently accepted as an *empty* override.
- `az containerapp job update --replica-retry-limit 0` **silently ignores the 0** (falsy) and leaves 1; the command reports success. Use `az rest` PATCH and read the value back. Terminal status appears ~2–3 min after `replicaTimeout` fires — don't treat the timeout as the moment `Failed` is readable.

Verify a Job deploy by asserting the **image tag on the Job**, never by curling a URL — a health-curl against an HTTP app is a paid wake-up (Guardrail #13). The Function App MI that starts jobs needs only a custom role with `Microsoft.App/jobs/read` + `jobs/start/action` scoped to the job; the built-in "Container Apps Contributor" has no `jobs/*` actions and grants no data plane. Allow 3–4 min for RBAC propagation on first use.

See [references/aca-jobs.md](references/aca-jobs.md).

## Multi-container sidecar pattern

A Container App can run multiple containers in a single replica, sharing `localhost` networking. Useful for embedded dependencies like a headless browser:

```yaml
template:
  containers:
    - name: app
      image: $ACR/app:$TAG
      env:
        - name: BROWSER_URL
          value: http://localhost:11235   # talks to sidecar
    - name: browser
      image: docker.io/unclecode/crawl4ai:0.8.6   # pin — avoid :latest drift
```

Apply via YAML to keep both containers atomic:

```bash
az containerapp update --name "$APP_NAME" --resource-group "$RG" --yaml app.yaml
```

See [references/sidecar-pattern.md](references/sidecar-pattern.md).

## Secrets via `secretref:`

Container App secrets are write-only — values can't be read back. Link to env vars:

```bash
az containerapp secret set --name "$APP_NAME" --resource-group "$RG" \
  --secrets "openai-key=$OPENAI_API_KEY"

az containerapp update --name "$APP_NAME" --resource-group "$RG" \
  --set-env-vars "OPENAI_API_KEY=secretref:openai-key"
```

**Gotcha: updating a secret value doesn't restart replicas.** Force a revision restart:

```bash
REVISION=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "properties.latestRevisionName" -o tsv)
az containerapp revision restart --name "$APP_NAME" --resource-group "$RG" --revision "$REVISION"
```

## Request timeout for SSE / WebSocket

Default is 240 seconds. Streaming connections drop at 4 minutes without this:

```bash
az containerapp ingress update --name "$APP_NAME" --resource-group "$RG" --request-timeout 1800
```

Maximum: 3600 (1 hour).

## Probes (health checks)

Liveness + readiness probes prevent traffic to a starting container and recycle stuck ones:

```yaml
probes:
  - type: liveness
    httpGet: { path: /health, port: 8000 }
    initialDelaySeconds: 10
    periodSeconds: 30
  - type: readiness
    httpGet: { path: /health, port: 8000 }
    initialDelaySeconds: 5
    periodSeconds: 10
```

See [references/probes.md](references/probes.md).

## Image registry — GHCR vs ACR

| Registry | When |
|----------|------|
| **GHCR** (ghcr.io) | Public images, GitHub-hosted projects. **Free for public repos.** |
| **Docker Hub** | Avoid anonymously (100 pulls/6h rate limit). Pin tags if used. |
| **ACR** (Azure Container Registry) | Private images, fine-grained RBAC. ~$5/month Basic tier. **Share one across projects** — an org-wide Basic registry costs the same as a per-project one. |

For non-secret images, GHCR is the cheapest option. For a shared ACR in *another* subscription: build server-side with `az acr build --subscription <acr-sub>` (OIDC login only scopes the app's subscription), pull with the app's system-assigned MI (`az containerapp registry set --identity system` + `AcrPull` on the registry), and give the CI SP **Contributor scoped to the registry resource** — `AcrPush` alone lacks the ARM read `az acr build` needs and fails with a misleading "could not be found in subscription". **Never delete a registry before repointing every consumer**: apps left on `ImagePullFailure` sit in `Activating` and bill full vCPU with `minReplicas: 0`. See [references/ghcr-vs-acr.md](references/ghcr-vs-acr.md).

## Retiring a Container App

Scaling down or updating a retired app leaves its revisions active and re-provisions a replica. To actually stop the spend:

1. `az containerapp revision list -n <app> -g <rg> --all --query "[?properties.active].name"` — deactivate **every** one (`az containerapp revision deactivate`); the newest isn't always the only active revision, and `--all` is needed to see deactivated ones.
2. Remove it from Bicep / IaC.
3. **`grep` every workflow and deploy script for the app name.** A workflow that still runs `az containerapp update` or `curl`s its `/health` recreates it on the next deploy — this happened twice in one month.
4. Add a network-free structural test that fails the build if the name reappears in `.github/workflows` or `deploy.sh`.
5. Prove it in **billing** (daily, per ResourceId), not in config (Guardrail #14).

## Dockerfile template

```dockerfile
FROM node:22-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --production

EXPOSE 8000
ENV NODE_ENV=production

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8000/health || exit 1

CMD ["node", "dist/server.js"]
```

Key points:
- Alpine for small images (faster cold start)
- Build with devDeps, then `npm prune --production`
- Use `wget` not `curl` (Alpine doesn't bundle curl)
- Always expose `/health`

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — for the modular toggle to add ACA
- [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md) — when the container uses blob storage
- [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md) — for the Log Analytics workspace + alerts
- Microsoft `azure-diagnostics` for live container debugging via the Azure MCP

## Templates

| File | Purpose |
|------|---------|
| [templates/containerApp.bicep](templates/containerApp.bicep) | HTTP Container App with scale-to-zero |
| [templates/containerAppJob.bicep](templates/containerAppJob.bicep) | Manual-trigger Container Apps Job |
| [templates/managedEnv.bicep](templates/managedEnv.bicep) | Shared managed environment (Consumption profile) |
| [templates/multi-container.yaml](templates/multi-container.yaml) | YAML for sidecar pattern |
| [templates/scale-config.json](templates/scale-config.json) | `az rest` PATCH body: cooldown 300 + HTTP rule + KEDA cron warm window |
| [../applying-azure-cost-guardrails/templates/costGuardrails.bicep](../applying-azure-cost-guardrails/templates/costGuardrails.bicep) | RG budget + "stuck-warm" Replicas alert per scale-to-zero app |
