# Composition with Microsoft's azure-diagnostics

This skill catalogues **known** failures with **known** fixes. For runtime / dynamic failures, delegate to Microsoft's diagnostics skills + the Azure MCP.

## When this skill answers

The symptom matches a documented gotcha. The fix is in the table or the gotcha catalogue.

Example: user says "I'm getting AADSTS70021" → match gotcha #12 → apply the fix.

## When to delegate to `azure-diagnostics`

The symptom is:
- A 500 / 502 / 503 from a deployed app
- Slow performance / latency spikes
- An exception trace that doesn't match a known pattern
- Resource state Claude can't see in the codebase (live config drift, scaling behaviour, replica health)
- A behavioural issue that requires log/metric queries to diagnose

Microsoft's `azure-diagnostics` + the Azure MCP can:
- Pull recent App Service / Container App / Function logs
- Query Log Analytics workspaces
- Inspect live resource state
- Fetch metric history

```
This skill (static catalogue) → if no match → Microsoft azure-diagnostics (live queries)
                                            → if needed → appinsights-instrumentation (add telemetry)
```

## Practical pattern

When a user reports a failure:

1. **First**, look at the message + state. Try to match a gotcha here.
2. If matched → apply the fix. Done.
3. If unmatched → ask: "Is the app deployed and running? What does the failure look like — a deploy step, a runtime error, or unexpected behaviour?"
4. If deploy step → check the workflow's recent runs:
   ```bash
   gh run list --limit 5
   gh run view <run-id>
   gh run view <run-id> --log-failed
   ```
5. If runtime → delegate to Microsoft `azure-diagnostics`:
   - "Pull recent logs from the Container App / Function App"
   - "What were the last 10 exceptions in App Insights?"
   - "Has the resource been scaling?"
6. Once the root cause is found and fixed, **capture it as a new gotcha** via [curating-azure-deployment-learnings](../../curating-azure-deployment-learnings/SKILL.md). The next person who hits it should find it in the static catalogue.

## What to NOT do

- Don't reinvent live diagnostics here. Microsoft's plugin has direct API access; we have grep against markdown.
- Don't promote a one-off project bug into a gotcha unless it's likely to recur for others.
- Don't paste 500-line logs into the catalogue — link to where the symptom was observed (Application Insights query URL, etc.) and document the fix concisely.
