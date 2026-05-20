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

- **`minReplicas: 0` for a websocket server**: existing connections drop when the replica scales to 0. Use `minReplicas: 1`.
- **`maxReplicas: 100` "just in case"**: each replica costs money. Set a realistic cap.
- **Aggressive concurrency target (e.g. `concurrentRequests: "1"`)**: causes thrashing — replicas constantly scaling up and down. 10–50 is usually a good target for typical Node.js apps.

## Verifying scale behaviour

```bash
# Watch replicas in real time
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" -o table

# Check what scale rules are active
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "properties.template.scale" -o json
```
