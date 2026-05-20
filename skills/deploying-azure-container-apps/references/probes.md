# Container Apps probes

Liveness + readiness probes are configured in the container template. They are evaluated by the Container Apps runtime, not the Docker `HEALTHCHECK` directive (which is ignored by ACA).

## Default behaviour without probes

Without probes:
- Container is considered ready immediately when it starts
- Traffic is sent to it as soon as the process listens on `targetPort`
- A stuck process is never recycled

This causes:
- 502s during cold start while the app is still booting
- Permanent broken state if the process hangs

## Pattern

```yaml
template:
  containers:
    - name: app
      image: ...
      probes:
        - type: liveness
          httpGet: { path: /health, port: 8000 }
          initialDelaySeconds: 10       # give the app time to start before checking
          periodSeconds: 30             # check every 30s
          failureThreshold: 3           # fail 3 in a row → restart container
          timeoutSeconds: 3
        - type: readiness
          httpGet: { path: /health, port: 8000 }
          initialDelaySeconds: 5        # readiness checks start sooner
          periodSeconds: 10
          failureThreshold: 3
          timeoutSeconds: 3
        - type: startup
          httpGet: { path: /health, port: 8000 }
          initialDelaySeconds: 0
          periodSeconds: 5
          failureThreshold: 30          # ~150s grace before giving up on startup
          timeoutSeconds: 3
```

## When each probe fires

| Probe | What it does |
|-------|-------------|
| `startup` | Runs until success once; gates liveness/readiness. Use when the app takes >initialDelaySeconds to boot (e.g. loading ML models). |
| `readiness` | When failing, the replica is removed from ingress rotation. When passing, traffic resumes. |
| `liveness` | When failing for `failureThreshold` consecutive checks, the container is restarted. |

## `/health` endpoint

Implement a fast endpoint that returns 200 if the process is alive:

```typescript
app.get('/health', (req, res) => res.status(200).json({ ok: true }));
```

**Don't** include heavy checks (DB connectivity, downstream APIs) in `/health` — a brief DB blip will cycle your container. Use a separate `/ready` endpoint for that and wire it to the `readiness` probe instead of `liveness`.

## Probe types other than `httpGet`

- `tcpSocket`: for non-HTTP services
- `exec`: runs a command inside the container; succeeds if exit code 0

```yaml
- type: liveness
  tcpSocket: { port: 6379 }            # for a Redis-like sidecar
- type: liveness
  exec:
    command: [/bin/sh, -c, "pgrep myproc"]
```
