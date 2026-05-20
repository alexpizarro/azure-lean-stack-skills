---
name: deploying-azure-container-apps
description: Deploys Docker containers to Azure Container Apps with scale-to-zero, multi-container sidecars, shared managed environments, and Container Apps Jobs for batch workloads. Use when SWA + FC1 don't fit — long-running servers, WebSocket/SSE streaming, custom Docker runtimes, scheduled or queue-driven background jobs, or multi-process workloads with sidecars.
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
| Idle (`minReplicas: 0`) | $0 |
| Active (0.25 vCPU, 0.5 GiB) | pennies/month at low traffic |
| Always warm (`minReplicas: 1`) | ~$5/month (no cold start) |
| Log Analytics workspace | bound by `dailyQuotaGb` on the workspace (see [instrumenting-azure-app-insights](../instrumenting-azure-app-insights/SKILL.md)) |

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

For run-to-completion workloads (batch processing, sync, scheduled crawls), use `Microsoft.App/jobs` instead of a Container App. A Job only runs when triggered; there are no idle replicas.

Triggers:
- `Manual` — started via `az containerapp job start` (with optional `--env-vars` for per-run inputs)
- `Schedule` — cron expression
- `Event` — Azure queue/event source

```bicep
resource job 'Microsoft.App/jobs@2024-03-01' = {
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
| **ACR** (Azure Container Registry) | Private images, fine-grained RBAC. ~$5/month Basic tier. |

For non-secret images, GHCR is the cheapest option. See [references/ghcr-vs-acr.md](references/ghcr-vs-acr.md).

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
