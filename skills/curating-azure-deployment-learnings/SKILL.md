---
name: curating-azure-deployment-learnings
description: Captures Azure deployment learnings from real projects in a structured format and promotes recurring ones into the diagnosing-azure-deployment-failures gotcha catalogue. Provides scripts to capture a new learning (with project, severity, frontmatter), diff against existing gotchas, and propose promotions with commit-ready text. Use when a deployment problem was solved and the fix should be captured so it doesn't have to be rediscovered, or when reviewing accumulated learnings to find patterns worth promoting.
---

# Curating Azure Deployment Learnings

The feedback loop that keeps the [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) gotcha catalogue current. Capture lessons from real projects in `learnings/`, then promote recurring ones into the catalogue.

> `learnings/` is **gitignored** in the plugin repo — learnings are private field notes (they name customers, subscriptions and costs). Only the *promoted* gotcha row is shared. The commit SHA recorded in a learning's Status line therefore points at the gotcha commit, and is for the author's own audit trail. Keep learnings in whichever private location suits you (`LEARNINGS_DIR` overrides the default for every script).

## When to invoke

- A deployment problem was solved — capture it before it's forgotten
- Reviewing accumulated `learnings/*.md` for promotion candidates
- Triaging which learnings are project-specific vs broadly reusable

## The pipeline

```
Project hits a problem in the field
   ↓
Solve it — file a learning in learnings/{date}_{project}.md
   ↓
Periodically review learnings/ — what shows up across multiple projects?
   ↓
Promote recurring ones to skills/diagnosing-azure-deployment-failures/references/gotchas.md
   ↓
Mark the learning entry "✅ Promoted in commit {sha}"
```

## Learning file format

```markdown
---
project: trg-directory-content-crawl
date: 2026-05-20
issues:
  - docker-hub-rate-limit
  - crawl4ai-pinning
severity: medium
promoted: false
---

# Session Learnings — TRG Directory Content Crawl

## Issue 1 — Docker Hub anonymous pulls hit rate limit in CI

### What happened
After 20+ successful deploys, the GitHub Actions runner started getting `toomanyrequests`
errors when pulling `unclecode/crawl4ai:latest`.

### Root cause
Docker Hub limits anonymous pulls to 100/6h per IP. GitHub-hosted runners share IPs,
so the project's pulls were rate-limited from other workflows on the same NAT IP.

### Fix applied
Pinned the image to `crawl4ai:0.8.6` and mirrored it into our ACR. Updated deploy.sh
and the Bicep template.

Files changed: `azure/deploy.sh:83`, `infra/modules/crawler.bicep:42`.

Status: ✅ Promoted — docker-hub-rate-limit → gotcha #31, crawl4ai-pinning → gotcha #38 (commit abc1234).
```

The frontmatter is machine-readable; the body is for humans.

## Severity rubric

| Severity | When |
|----------|------|
| **high** | Blocks deploys completely; affects every project of this shape |
| **medium** | Slows down deploys, requires workaround, but project-specific or only sometimes |
| **low** | Cosmetic / one-off / specific to this project's environment |

Only `high` and `medium` are promotion candidates by default.

## Scripts

### `capture-learning.sh`

Interactive wrapper that creates a properly-formatted file:

```bash
bash skills/curating-azure-deployment-learnings/scripts/capture-learning.sh
# Prompts for: project slug, issue tags (comma-separated), severity, then opens the file in $EDITOR
```

### `review-learnings.sh`

Scans `learnings/*.md`, groups by issue tag, and identifies promotion candidates:

```bash
bash skills/curating-azure-deployment-learnings/scripts/review-learnings.sh

# Output:
# Issue tag                       | Severity | Projects | Status
# --------------------------------|----------|----------|------------
# docker-hub-rate-limit           | medium   |        3 | PROMOTE
# crawl4ai-pinning                | medium   |        2 | PROMOTE
# fc1-cli-silent-fallback         | high     |        4 | already in gotchas
# trg-specific-cms-quirk          | low      |        1 | skip
```

### `promote-to-gotchas.sh`

Given an issue tag, generates the markdown row to add to `gotchas.md`:

```bash
bash skills/curating-azure-deployment-learnings/scripts/promote-to-gotchas.sh docker-hub-rate-limit

# Output: the learnings that carry the tag, then a blank row skeleton to fill in:
# | N | <Symptom> | <Root cause> | <Fix> |
```

Number it `max(existing) + 1` and insert it under the most relevant category (numbers are stable ids, not positions).

## Verify before you promote

A reviewer reading only source and config will confidently describe failure modes that don't exist. During the 2026-07 ACA idle-burn review, two strong models produced five plausible P1 findings that one live query each disproved — and the author's own first draft carried a false platform rule ("external ingress can't scale to zero") reached by reasoning from a single pinned app. Before a learning becomes a gotcha:

1. **Find a counter-example**, not a confirmation: if the claim is "X always causes Y", query the estate for X without Y.
2. Prefer a live read (`az … show`, billing by ResourceId, replica list) over a screenshot of config.
3. If the claim is about cost, prove it in daily billing per resource (cost-guardrails Guardrail #14).

## Promotion criteria

A learning is ready to promote when:

- It appears in **≥2 different projects**, OR
- It's severity **high** (every project of that shape will hit it)
- AND the fix is reproducible — not "we restarted the runner"
- AND it's not already in the gotcha catalogue
- AND it's broadly applicable — not "this customer's CMS has a bug"

## After promoting

1. Add the gotcha row to `skills/diagnosing-azure-deployment-failures/references/gotchas.md`
2. Update the quick symptom table in `SKILL.md` if symptoms match
3. Update each contributing learning's frontmatter: `promoted: true` and add commit SHA in the Status line
4. Commit with message: `docs(gotchas): promote {issue-tag} from learnings`

## Anti-patterns

- **Logging every minor papercut as a learning** — only file when the fix is non-obvious and likely to recur
- **Promoting one-project incidents** — if it only happened once and you can't see why it would recur, the entry stays in learnings/ for context but doesn't go to gotchas
- **Treating gotchas as commit messages** — gotchas are about *what to do when you hit symptom X*, not *what changed in commit Y*. Keep entries action-oriented

## Composes with

- [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) — destination for promoted learnings
- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — many infrastructure learnings become Bicep template improvements too, not just gotchas
