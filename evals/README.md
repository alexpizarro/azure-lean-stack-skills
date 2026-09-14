# Evals

Three-scenarios-per-skill evaluation harness for Azure Lean Stack.

## Format

Each `*.json` file is one scenario:

```json
{
  "skill": "name-of-skill-being-tested",
  "query": "User prompt to Claude (verbatim)",
  "context": "Optional setup context Claude needs",
  "expected_behavior": [
    "Claude should do X",
    "Claude should NOT do Y",
    "If asked, Claude should reference Z"
  ],
  "ground_truth": {
    "must_invoke": ["skill-A", "skill-B"],
    "may_invoke": ["skill-C"],
    "must_not_invoke": ["skill-Z"],
    "must_run_commands": ["az some-command pattern"],
    "must_avoid_commands": ["az functionapp create --flexconsumption-location"],
    "must_mention": ["phrase the answer must contain"],
    "must_have_in_bicep": ["dailyQuotaGb"],
    "must_not_have_in_bicep": ["tierToArchive"],
    "must_warn_before_implementing": true,
    "must_not_produce": ["a handler that queries the DB on every call"]
  }
}
```

All `ground_truth` keys are optional; use the ones the scenario needs.

## How to use

The harness for running these is not built yet — they currently exist as a
**review specification**. For each new skill change:

1. Read the relevant `*.json` files in this directory.
2. Open a fresh Claude Code session.
3. Send the `query` (with `context` if any).
4. Verify Claude's behaviour matches `expected_behavior` and `ground_truth`.
5. If it deviates, the SKILL.md/description needs fixing, not the eval.

Run the same scenario on:
- **Haiku** (fastest, hardest — needs explicit instructions)
- **Sonnet** (baseline)
- **Opus** (most capable — usually passes; if it doesn't, the skill is broken)

## Coverage targets

| Skill | Scenarios shipped | Scenarios target |
|-------|------------------|------------------|
| orchestrating-azure-deployments | 1 | 3 |
| scaffolding-azure-bicep-infrastructure | 1 | 3 |
| diagnosing-azure-deployment-failures | 1 | 3 |
| developing-azure-apps-locally | 1 | 3 |
| applying-azure-cost-guardrails | 2 | 3 |
| deploying-azure-container-apps | 1 | 3 |
| (all other 11 skills) | 0 | 3 |

Adding more scenarios is a high-leverage contribution.
