# Multi-container sidecar pattern

A Container App replica can run multiple containers sharing `localhost` networking. Useful when the main app needs an embedded dependency (headless browser, vector DB, local cache).

## Pattern

```yaml
properties:
  configuration:
    ingress:
      external: true
      targetPort: 8000               # ingress goes to the primary container's port
      transport: auto
  template:
    containers:
      - name: app                    # primary — ingress points here
        image: ghcr.io/org/app:0.5.0
        resources:
          cpu: 0.75
          memory: 1.5Gi
        env:
          - name: SIDECAR_URL
            value: http://localhost:11235   # talks to sidecar over localhost
        probes:
          - type: liveness
            httpGet: { path: /health, port: 8000 }
            initialDelaySeconds: 10
            periodSeconds: 30
          - type: readiness
            httpGet: { path: /health, port: 8000 }
            initialDelaySeconds: 5
            periodSeconds: 10
      - name: browser                # sidecar — internal only
        image: docker.io/unclecode/crawl4ai:0.8.6    # PINNED — avoid :latest drift
        resources:
          cpu: 0.75
          memory: 1.5Gi
        env:
          - name: API_TIMEOUT
            value: "60"
    scale:
      minReplicas: 0
      maxReplicas: 3
      rules:
        - name: http-scaling
          http:
            metadata:
              concurrentRequests: "5"
```

Apply via:

```bash
az containerapp update --name "$APP_NAME" --resource-group "$RG" --yaml app.yaml
```

## Resource limits

Each container has independent `cpu` / `memory`. Replica total = sum of all containers:

| Container | CPU | Memory |
|-----------|-----|--------|
| app       | 0.75 vCPU | 1.5 GiB |
| browser   | 0.75 vCPU | 1.5 GiB |
| **Total** | **1.5 vCPU** | **3 GiB** |

Max replica size: 4 vCPU / 8 GiB (Consumption workload profile).

## Cost implications

- Cold start: both containers must be ready before traffic is served (~5–15s typical, longer for image-heavy sidecars like Chromium)
- Idle cost: $0 when `minReplicas: 0`
- Active cost: pays for the sum of all containers' resource usage

## Always pin sidecar images

Sidecars are often public images (Chromium, Redis, FAISS). Pin to a specific tag — `:latest` will drift and break your app silently:

```yaml
image: docker.io/unclecode/crawl4ai:0.8.6      # GOOD
image: docker.io/unclecode/crawl4ai:latest     # BAD — drift risk
```

## Communication

Containers in the same replica share network namespace. Use `localhost:{port}`:

```typescript
const response = await fetch('http://localhost:11235/scrape', { ... });
```

No service discovery needed; no DNS lookup.

## When NOT to use sidecars

- The dependency has a managed Azure equivalent (e.g. Redis → Azure Cache for Redis)
- Two containers don't share lifecycle (one outlives the other) — they belong in separate Container Apps
- The sidecar is heavy and frequently restarted — replica startup time multiplies

## Health checks

Both containers should expose `/health`. Only the primary's probe is wired to ingress, but you want the sidecar's liveness probe to recycle a stuck container without taking the whole replica down.
