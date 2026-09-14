# Scale-to-zero on Container Apps

Container Apps scales replicas based on traffic. Setting `minReplicas: 0` means $0 idle cost — but introduces cold-start latency.

## Configuration

```yaml
scale:
  minReplicas: 0                    # scale-to-zero on
  maxReplicas: 3
  rules:
    - name: http-scaling
      http:
        metadata:
          concurrentRequests: "10"   # add a replica per 10 concurrent requests
```

## `cooldownPeriod` — the second `minReplicas`

`scale.cooldownPeriod` (default **300** s) is how long the last replica stays alive after traffic stops. If it is longer than the typical gap between requests the alive window never closes and the app is always-on — with `minReplicas: 0` still showing in the portal. Measured: `cooldownPeriod: 7200` with one request every ~18 min = pinned 24/7, ~A$2/day to serve 26 requests per 8 hours (gotcha #42). Leave it at 300. For a known busy window use a KEDA `cron` rule (below); for "cold starts hurt all day" use `minReplicas: 1` explicitly so the cost is visible.

## Warm window with a KEDA `cron` rule

```yaml
scale:
  minReplicas: 0
  maxReplicas: 3
  cooldownPeriod: 300
  rules:
    - name: http-scaling
      http: { metadata: { concurrentRequests: "20" } }
    - name: class-night-warm
      custom:
        type: cron
        metadata:
          timezone: Australia/Sydney      # IANA — DST handled by the platform
          start: "45 17 * * 2"            # Tue 17:45
          end: "30 23 * * 2"              # Tue 23:30
          desiredReplicas: "1"
```

KEDA takes `max()` across rules, so the cron rule is a dynamic minimum and HTTP still scales up inside the window. Requires `activeRevisionsMode: Single`. Date-pinned one-offs (`0 13 29 8 *` → `55 23 29 8 *`) work too — start and end are independent matches, so a window can span days; delete spent one-offs on the next change. The CLI has no flag for any of this: use `az rest --method PATCH` with the full `rules` array (`templates/scale-config.json`).

## Cold-start behaviour

| Image type | Typical cold start |
|------------|-------------------|
| Node.js Alpine, small bundle | 5–10s |
| Node.js Alpine, large deps | 10–20s |
| Python with ML libs | 15–30s |
| Chromium / heavy sidecar | 20–60s |

The cold-start clock includes:
1. Pulling the image (cached after first pull)
2. Container start
3. App boot until `readiness` probe passes
4. First request

## When to break scale-to-zero

Keep `minReplicas: 1` (small, always-warm) when:
- Users expect sub-2s response for the first request
- Cold start is >10s and that's user-visible
- The app holds expensive in-memory state (caches, ML models)

Cost: ~$5/month for one always-warm 0.25vCPU/0.5GiB replica.

## Scale rules — beyond HTTP

| Rule type | Use for |
|-----------|---------|
| `http` | Standard web traffic, by concurrent requests |
| `tcp` | TCP-based services by connection count |
| `cpu` / `memory` | Resource-based scaling (CPU-heavy workers) |
| `azure-servicebus` | Queue depth on Service Bus |
| `azure-queue` | Storage queue depth |
| `azure-eventhub` | Event Hub partitions |
| `cron` | Schedule-based scaling (e.g. minReplicas=2 during business hours) |

Example for a worker scaled by queue depth:

```yaml
scale:
  minReplicas: 0
  maxReplicas: 10
  rules:
    - name: queue-scaler
      custom:
        type: azure-queue
        metadata:
          queueName: jobs
          queueLength: "5"                # 1 replica per 5 queued messages
          accountName: mystorage
        auth:
          - secretRef: storage-conn-str
            triggerParameter: connection
```

## Anti-patterns

- **`minReplicas: 0` for a websocket server**: existing connections drop when the replica scales to 0. Use `minReplicas: 1` — and say so in a comment; cost-guardrails warns before any `minReplicas: 1`.
- **Raising `cooldownPeriod` to "avoid cold starts"**: functionally `minReplicas: 1`, invisibly. Use a cron warm window instead.
- **A status page that polls the app on `setInterval`**: 2,880 hits/day per open tab, including background tabs. Probe on demand or gate on `document.visibilityState`.
- **`maxReplicas: 100` "just in case"**: each replica costs money. Set a realistic cap.
- **Aggressive concurrency target (e.g. `concurrentRequests: "1"`)**: causes thrashing — replicas constantly scaling up and down. 10–50 is usually a good target for typical Node.js apps.

## Verifying scale behaviour

Read **running replicas**, never revisions. A revision is created at deploy time and stays `active` for months while running zero replicas; a revision-based "stuck warm" check produced 6 false positives out of 6 in a real estate. An empty `replica list` is the healthy scaled-to-zero state.

```bash
# Watch replicas in real time (empty output = scaled to zero)
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" -o table
# Sweep every app in every subscription
bash skills/applying-azure-cost-guardrails/scripts/check-live-replicas.sh

# Check what scale rules are active
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "properties.template.scale" -o json
```
