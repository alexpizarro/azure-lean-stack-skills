# Logic Apps Consumption vs Power Automate

The decision matrix for Microsoft consultants who need to move a flow off Power Automate (or pick the right tool for a new requirement).

## Cost comparison

| Plan | Pricing | Best for |
|------|---------|----------|
| **Logic Apps Consumption** | $0.000025/action | Backend automations, recurring HTTP triggers, no user context. **This skill.** |
| Power Automate Per-User | $15/user/month, 40k actions/day per user | User-driven flows, M365 integrations as the signed-in user |
| Power Automate Per-Flow | $100/flow/month, 250k actions/day | High-volume specific flows where pricing per-user doesn't scale |
| Logic Apps Standard | $200+/month (WS1 plan) | High-volume, latency-sensitive, VNet-integrated. **NOT yet proven in this skill pack.** |

## When Logic Apps Consumption wins

- Recurring trigger (cron-style)
- Pure HTTP / queue / event triggers — no human in the loop
- Backend integrations: webhook receiver, data sync, polling job
- Cadence between 1 minute and "once a day"
- Total action count below ~100k/month

Example: a flow that runs every 5 minutes and makes one HTTP call = $0.22/month. Same flow in Power Automate Per-User = $15/user/month.

## When Power Automate wins

- The flow must run "as the signed-in user" (e.g. read **my** SharePoint, send mail from **my** mailbox)
- Approval flows where humans click buttons in Teams
- Document AI (AI Builder) integrations
- A business user is supposed to maintain the flow visually

If the flow is the kind a Power Platform consultant would build for a client to own, it stays in Power Automate. If it's a piece of infrastructure that should be invisible to the client, lift it to Logic Apps Consumption.

## When Logic Apps Standard wins

- Action volume above ~100k/month — at scale the Consumption per-action pricing exceeds the Standard plan fee
- VNet integration / private endpoints required
- Long-running stateful workflows
- Custom connectors not available in Consumption

**Not yet proven in this skill pack.** A standalone `building-logic-apps-standard-workflows` skill can be added when a real project ships on it.

## Connectors

| Connector type | Consumption | Standard | Power Automate |
|---------------|-------------|----------|----------------|
| Standard connectors | ✓ free | ✓ free | ✓ included |
| Premium connectors | $$ per execution | included in WS1 plan | needs Premium licence |
| Custom connectors | ✓ | ✓ | ✓ (with Premium) |
| Connectors requiring user OAuth | limited | limited | ✓ |

## Workflow definition portability

All three runtimes (Consumption, Standard, Power Automate) use the **same `Microsoft.Logic/workflows` definition language**. A flow's JSON definition often ports directly — what changes is the host resource, connection bindings, and (for Power Automate) the UI it's edited in.

If you have a Power Automate flow you want to migrate:
1. Export the flow as a JSON ZIP from `make.powerautomate.com`
2. Extract the `workflow.json` body
3. Replace any user-context connections with HTTP / shared-secret patterns
4. Drop the body into the `definition:` block of `recurring-http-scheduler.bicep` (or a fuller Logic Apps Consumption resource)

## Anti-patterns

- **Using Consumption for sub-minute polling.** Minimum recurrence is 1 minute. For faster polling, use a Functions timer trigger.
- **Using Consumption when you have a premium connector in the path.** Some premium connectors carry a per-execution surcharge that can multiply Consumption pricing by 10–100×.
- **Treating Logic Apps as a microservice host.** It's a workflow runtime, not a server. If you have business logic, put it in a Function or Container App and call it from the Logic App.
