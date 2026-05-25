---
name: scheduling-with-azure-logic-apps-consumption
description: Creates Azure Logic Apps on the Consumption tier for recurring HTTP triggers and lightweight Power-Automate-style flows. Costs ~$0.22/month for a 5-minute recurrence (~8,640 actions at $0.000025 each). Use when adding a scheduled webhook ping, polling a SharePoint list, ticking a microservice every N minutes, or graduating a Power Automate flow that has hit its limits.
---

# Scheduling with Azure Logic Apps (Consumption tier)

Lightweight recurring triggers on Azure. Consumption tier bills per action (~$0.000025), so a 5-minute schedule runs about 8,640 actions a month — about 22 cents.

## When to invoke

- Adding a recurring HTTP trigger to your app (cache invalidation, heartbeat ping, recrawl tick)
- A Microsoft consultant client has hit Power Automate's plan limits for a backend-only flow and you need to migrate it
- Polling a SharePoint list / Teams channel / external API on a cadence
- Anything that used to be a `cron` job on a VM and shouldn't need a VM

## When NOT to invoke

- **Anything that needs user context.** Logic Apps Consumption can't sign in as the user. Power Automate is the right tool there.
- **Long-running flows with many actions.** At 100k+ actions/month, switch to Logic Apps Standard (consumption-priced compute, but Workflow Standard plan). Standard is **not currently proven** in this skill pack — add it only when a real project uses it.
- **Workflows requiring premium connectors.** Some connectors (Salesforce, SAP) carry a per-execution surcharge that changes the cost model.
- **Sub-minute cadence.** Logic Apps minimum recurrence is 1 minute. For sub-minute, use Functions timer triggers or Container Apps.

## ⚠️ Cost warning — don't point a frequent scheduler at a DB-backed endpoint

A recurring scheduler that hits an endpoint which queries a **SQL Serverless** database resets the DB's auto-pause timer on every run. At a 5-minute cadence the DB never pauses and bills compute 24/7 — the Logic App costs $0.22/mo, but the kept-awake database can cost far more.

**Proven failure:** `trg-directory-website`'s recrawl scheduler polled an endpoint that read `recrawl_queue` every 5 minutes, keeping the serverless DB awake (see [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) Guardrail #11).

Before wiring a scheduler to an app endpoint, confirm:
- The target endpoint is **DB-free** (e.g. the shallow `/api/health`), or
- The work genuinely needs the DB on every run AND you've accepted always-on cost → switch the DB to **flat Basic tier** (~$5/mo, cheaper than kept-awake serverless), or
- The cadence is infrequent enough that the DB still pauses between runs (interval > `autoPauseDelay`).

## Cost reality check

```
8,640 executions/month at $0.000025 each   →  $0.216/month       (5-minute cadence, single HTTP action)
17,280 executions × 1 HTTP action          →  $0.43/month        (3-minute cadence)
2,880 executions × 1 HTTP action           →  $0.07/month        (15-minute cadence)
```

Add ~$0.000025 per additional action in the flow. A workflow with 5 actions running every 5 minutes ≈ $1.10/month.

For a Microsoft-consultant audience: this is often 1% of the equivalent Power Automate Per-User plan ($15/user/month) for a backend-only flow.

## Proven pattern: recurring HTTP scheduler

The reference implementation is the recrawl scheduler in `trg-directory-website`: a Logic App that POSTs to an internal API endpoint every 5 minutes. The skill ships two equivalent forms of the same pattern:

- **Bicep template** ([templates/recurring-http-scheduler.bicep](templates/recurring-http-scheduler.bicep)) — preferred for production projects. Lives next to the rest of your IaC; one `az deployment group create` provisions it.
- **One-shot bash script** ([scripts/create-recurring-scheduler.sh](scripts/create-recurring-scheduler.sh)) — convenience wrapper for "I need this running by end of day" tasks. Mirrors the original trg-directory-website script.

Both implement:
- `Recurrence` trigger with configurable interval (minutes/hours/days)
- One HTTP `POST` action with a custom header (typically a shared secret) and optional JSON body
- Idempotent provisioning (`update` if exists, `create` if not)

## Workflow checklist

Copy this checklist into your response and track progress:

```
Logic App scheduler setup:
- [ ] Step 1: Confirm the resource group exists in the target environment branch
- [ ] Step 2: Identify the endpoint URL the schedule will POST to
- [ ] Step 3: Generate or fetch the shared-secret header value
- [ ] Step 4: Choose the recurrence (minutes/hours, interval) and re-check the cost
- [ ] Step 5: Deploy via Bicep (templates/recurring-http-scheduler.bicep) OR run scripts/create-recurring-scheduler.sh
- [ ] Step 6: Verify the first run fired (Logic App run history)
- [ ] Step 7: Add disable/enable commands to the project's runbook
```

### Step 1 — Resource group exists

The Logic App should live in the same resource group as the endpoint it calls. If you're deploying via the standard Azure Lean Stack workflow, the RG already exists.

### Step 2 — Endpoint URL

Get the SWA hostname or Container App FQDN. Typical shape:

```
https://{org}-{project}-swa-{env}.azurestaticapps.net/api/_internal/process-recrawl
https://{org}-{project}-aca-{env}.{region}.azurecontainerapps.io/scheduled-task
```

### Step 3 — Shared secret

The endpoint should refuse unauthenticated calls. Add a header (e.g. `x-scheduler-key`) and validate it server-side:

```typescript
if (req.headers.get('x-scheduler-key') !== process.env.SCHEDULER_KEY) {
  return { status: 401 };
}
```

Generate the secret once (e.g. `openssl rand -base64 32`) and store it as a GitHub secret + app setting. Don't bake it into Bicep.

### Step 4 — Recurrence

`frequency`: `Minute` | `Hour` | `Day` | `Week`
`interval`: integer ≥ 1

Minimum: 1-minute interval. Below that, switch to a Functions timer trigger.

### Step 5 — Deploy

Bicep (preferred):

```bash
az deployment group create \
  --resource-group "$RG" \
  --template-file skills/scheduling-with-azure-logic-apps-consumption/templates/recurring-http-scheduler.bicep \
  --parameters \
    name="$ORG-$PROJECT-sched-$ENV" \
    endpoint="$ENDPOINT" \
    schedulerSecret="$SCHEDULER_KEY" \
    intervalMinutes=5
```

Bash script (one-off):

```bash
ORG=acme PROJECT=taskapp ENV=test \
  ENDPOINT="https://.../api/_internal/recrawl" \
  SCHEDULER_KEY="$(openssl rand -base64 32)" \
  bash skills/scheduling-with-azure-logic-apps-consumption/scripts/create-recurring-scheduler.sh
```

### Step 6 — Verify

```bash
# Show recent runs
az logic workflow run list \
  --name "$LOGIC_APP" --resource-group "$RG" \
  --query "[].{started:startTime,status:status,code:code}" -o table
```

A successful run shows `status: Succeeded`.

### Step 7 — Runbook lines

Add to your project CLAUDE.md / README:

```bash
# Pause the scheduler (e.g. during maintenance)
az logic workflow update --name "$LOGIC_APP" --resource-group "$RG" --state Disabled

# Resume
az logic workflow update --name "$LOGIC_APP" --resource-group "$RG" --state Enabled
```

## Proven in

- `trg-directory-website` — the `create-recrawl-scheduler.sh` script in its `scripts/` directory deploys this exact pattern. Logic App name: `trg-recrawl-scheduler-{env}`. 5-minute recurrence. Documented cost: ~$0.22/month.

## Migration path: Power Automate → Logic Apps Consumption

When a client's Power Automate flow has hit the 5,000-action/day limit on the included $15/user plan, and the flow is:
- HTTP-triggered (recurrence or webhook)
- Doesn't need user context (no "as the signed-in user" connectors)
- Uses standard connectors (no premium)

…then Logic Apps Consumption is usually a 50× cost reduction. Both use the same workflow definition language (`Microsoft.Logic/workflows`), so the JSON definition often ports directly.

If the flow uses Office 365 / SharePoint connectors with user context, it stays in Power Automate.

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — for the project's main Bicep + naming formula
- [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md) — typical endpoint host
- [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) — the per-execution math
