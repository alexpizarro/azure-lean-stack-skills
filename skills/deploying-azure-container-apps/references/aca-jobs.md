# Container Apps Jobs

Run-to-completion workloads on the same Consumption profile as Container Apps. **No idle billing** — a Job runs only when triggered.

## When to use a Job vs a Container App

| Workload | Use |
|----------|-----|
| HTTP API serving requests | Container App |
| Batch processor running for N minutes | **Job (Manual or Schedule)** |
| Scheduled crawler / sync | **Job (Schedule)** |
| Queue-driven worker | **Job (Event)** |
| Always-on background task | Container App with `minReplicas: 1` |

## Trigger types

### Manual

Started by `az containerapp job start`. Per-invocation inputs via `--env-vars`. Use for "do this thing now" workflows where an upstream API kicks off the job.

```bicep
configuration: {
  triggerType: 'Manual'
  replicaTimeout: 3600                  // max single-run wall clock (seconds)
  replicaRetryLimit: 1                  // retry once on failure
  manualTriggerConfig: {
    parallelism: 1                      // how many replicas at once
    replicaCompletionCount: 1           // how many must succeed for the run to count
  }
}
```

Trigger:

```bash
az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --env-vars "TASK_ID=$ID" "INPUT_BLOB=$URI"
```

### Schedule

Cron-style. Use for nightly syncs, periodic crawls.

```bicep
configuration: {
  triggerType: 'Schedule'
  replicaTimeout: 1800
  scheduleTriggerConfig: {
    cronExpression: '0 2 * * *'          // 02:00 UTC daily
    parallelism: 1
    replicaCompletionCount: 1
  }
}
```

### Event

Queue-driven via Azure Service Bus, Storage Queue, Event Hub, Kafka.

```bicep
configuration: {
  triggerType: 'Event'
  eventTriggerConfig: {
    parallelism: 5                       // scale up to 5 parallel replicas
    replicaCompletionCount: 1
    scale: {
      maxExecutions: 10
      pollingInterval: 30
      rules: [
        {
          name: 'queue-scaler'
          type: 'azure-queue'
          metadata: {
            queueName: 'jobs'
            queueLength: '5'             // 1 replica per 5 queued messages
            accountName: 'mystorage'
          }
        }
      ]
    }
  }
}
```

## Traps when driving Jobs from code or CLI

| Trap | Reality |
|---|---|
| `az containerapp job update --replica-retry-limit 0` | Silently ignores the `0` (treated as falsy) and leaves it at 1 — reports success. Use `az rest --method PATCH` and read the value back. |
| `POST .../jobs/{name}/start` with `{ "env": [...] }` | The body **replaces the whole container env**, dropping every secretRef-backed var. GET the job, clone `template.containers[0]`, append, then POST. |
| Wrapping the start body in `{ "template": {...} }` | Silently accepted as an *empty* override — the job runs with stock env and exits non-zero. The body is a top-level `JobExecutionTemplate`: `{ "containers": [...], "initContainers": [...] }`. |
| Polling for `Failed` at exactly `replicaTimeout` | Terminal status lands ~2–3 min after the cap fires (propagation + 60s poll granularity). |
| Verifying a deploy by `curl`ing an HTTP app's `/health` | A paid wake-up. Assert the Job's image tag instead: `az containerapp job show --query "properties.template.containers[0].image"`. |
| Starting the job from an app's managed identity | Built-in "Container Apps Contributor" has no `Microsoft.App/jobs/*` actions. Create a custom role with `jobs/read` + `jobs/start/action` (+ `jobs/executions/read`) scoped to the job. |

## Secrets and private images

Jobs use the same `secrets:` + `secretref:` pattern as Container Apps:

```bicep
configuration: {
  registries: [
    {
      server: 'ghcr.io'
      username: 'set-by-github-actions'
      passwordSecretRef: 'ghcr-pull'
    }
  ]
  secrets: [
    { name: 'ghcr-pull', value: 'set-by-github-actions' }
    { name: 'storage-key', value: 'set-by-github-actions' }
  ]
}
template: {
  containers: [{
    env: [
      { name: 'AZURE_STORAGE_KEY', secretRef: 'storage-key' }
    ]
  }]
}
```

## Workload profile

Always use `Consumption` for cost. Dedicated profiles (D4/D8) bill per-minute even when idle.

```bicep
workloadProfileName: 'Consumption'
```

On the managed environment:

```bicep
workloadProfiles: [
  { name: 'Consumption', workloadProfileType: 'Consumption' }
]
```

## Monitoring a Job run

```bash
# Latest run
az containerapp job execution list --name "$JOB_NAME" --resource-group "$RG" \
  --query "[0].{name:name,status:properties.status,startedAt:properties.startTime}" -o json

# Logs from a specific execution
az containerapp job execution show \
  --name "$JOB_NAME" --resource-group "$RG" --job-execution-name "$EXEC_NAME"
```

For deeper logs, query Log Analytics:

```bash
az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerJobName_s == '$JOB_NAME' | order by TimeGenerated desc | take 100"
```
