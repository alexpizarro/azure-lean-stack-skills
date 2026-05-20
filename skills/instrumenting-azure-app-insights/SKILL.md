---
name: instrumenting-azure-app-insights
description: Provisions workspace-based Azure Application Insights with a dailyQuotaGb cost cap and optional metric alerts (5xx spikes, server exceptions) on an Action Group. Outputs the connection string for app settings wiring (APPLICATIONINSIGHTS_CONNECTION_STRING). Use when adding observability to a project, replacing classic non-workspace App Insights (which is retiring), or setting up failure alerts that email an on-call owner.
---

# Instrumenting Azure Application Insights

Workspace-based Application Insights with cost guardrails. Classic (non-workspace) App Insights is retiring, so this is the only forward-compatible setup.

## When to invoke

- Adding observability to a new project
- Migrating off classic Application Insights
- Setting up failure-rate alerts that page an owner
- Auditing observability cost on an existing app

## The two-resource setup

App Insights now sits on top of a Log Analytics workspace:

```
Log Analytics Workspace  ← cost guardrail lives here (dailyQuotaGb)
       ↑
       │  WorkspaceResourceId
       │
Application Insights component  ← what the SDK talks to
       ↑
       │  APPLICATIONINSIGHTS_CONNECTION_STRING
       │
Your app's instrumented SDK
```

Workspace owns:
- Retention (`retentionInDays: 30` default; max 730)
- Daily quota cap (`workspaceCapping.dailyQuotaGb: 1`)
- All actual data storage

App Insights component owns:
- The connection string the SDK uses
- Per-app filtering / sampling rules

## Cost guardrail: `dailyQuotaGb`

The single most important setting. Without it, a runaway log loop can ingest 100+ GB and bill hundreds of dollars overnight.

```bicep
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: 1 }    // ← hard daily cap
  }
}
```

Rule of thumb:
- Hobby / low-traffic: 1 GB/day cap (~$2/month at default rates)
- Small SaaS: 5 GB/day cap
- Production with structured logging: start at 5, monitor, raise as needed

Once the cap is hit, ingestion is paused for the rest of the UTC day. You'll lose log lines but not the bill.

## Optional metric alerts

When `alertEmail` is non-empty, the module creates:

1. **Action Group** — sends to the email (could be extended to SMS, webhook, etc.)
2. **5xx alert** — fires if `requests/failed > 5` in any 15-min window
3. **Exceptions alert** — fires if `exceptions/server > 5` in any 15-min window

```bicep
resource failedRequestsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (createAlerts) {
  properties: {
    severity: 1
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [{
        metricName: 'requests/failed'
        operator: 'GreaterThan'
        threshold: 5
        timeAggregation: 'Count'
      }]
    }
  }
}
```

Tune thresholds per app. The defaults are conservative — most low-traffic apps stay quiet, and a single bad deploy fires the alert.

## Wiring the connection string

The Bicep outputs the connection string. The workflow sets it as a SWA / Function App / Container App setting:

```bash
# SWA
az staticwebapp appsettings set --name "$SWA_NAME" --resource-group "$RG" \
  --setting-names APPLICATIONINSIGHTS_CONNECTION_STRING="$CONN_STR"

# Container App
az containerapp update --name "$ACA_NAME" --resource-group "$RG" \
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=$CONN_STR"
```

The SDK auto-detects this env var and starts emitting telemetry.

## Auto-instrumentation in code

### Azure Functions (Node 22)

```typescript
// api/src/index.ts — at the top, before any other imports
import { useAzureMonitor } from '@azure/monitor-opentelemetry';

if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  useAzureMonitor();
}

import './functions/hello';
import './functions/getItems';
// ...
```

### Express / standalone Node

```typescript
import { useAzureMonitor } from '@azure/monitor-opentelemetry';
useAzureMonitor();   // reads APPLICATIONINSIGHTS_CONNECTION_STRING from env

import express from 'express';
const app = express();
// ... app receives auto-instrumented HTTP traces
```

## Querying useful metrics

```kusto
// 5xx in the last 24h, by endpoint
requests
| where timestamp > ago(24h)
| where success == false
| summarize count() by operation_Name, resultCode
| order by count_ desc

// Slowest endpoints (p95) over 7d
requests
| where timestamp > ago(7d)
| summarize p95 = percentile(duration, 95) by operation_Name
| order by p95 desc

// Recent server exceptions
exceptions
| where timestamp > ago(1h)
| project timestamp, type, outerMessage, operation_Name
| order by timestamp desc
```

## Pricing summary

| Item | Cost |
|------|------|
| Ingestion | ~$2.30/GB ingested |
| 30-day retention | included in ingestion |
| 90+ day retention | ~$0.10/GB/month per extra day |
| Alert rules | ~$0.10/rule/month |
| Action Group emails | free |
| SMS notifications | ~$0.55/notification |

A small app with 100 MB/day ingestion + 2 alerts ≈ $7/month.

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — `deployObservability: true` toggle
- [deploying-azure-container-apps](../deploying-azure-container-apps/SKILL.md) — uses the same workspace for container logs
- [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) — `dailyQuotaGb` is one of the canonical guardrails
- Microsoft's `appinsights-instrumentation` skill — for deeper SDK / query patterns

## Templates

| File | Purpose |
|------|---------|
| [templates/applicationInsights.bicep](templates/applicationInsights.bicep) | Workspace + App Insights + optional alerts |
