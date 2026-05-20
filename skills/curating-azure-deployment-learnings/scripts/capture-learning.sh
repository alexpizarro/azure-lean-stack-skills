#!/usr/bin/env bash
# Interactive: capture a new Azure deployment learning into learnings/.
#
# Output: learnings/YYYY-MM-DD_{project-slug}.md with proper frontmatter.

set -euo pipefail

LEARNINGS_DIR="${LEARNINGS_DIR:-learnings}"
mkdir -p "$LEARNINGS_DIR"

echo "─── Capture Azure deployment learning ───"
echo ""

read -rp "Project slug (e.g. acme-taskapp): " PROJECT
[[ -z "$PROJECT" ]] && { echo "ERROR: project required" >&2; exit 1; }

read -rp "Issue tags (kebab-case, comma-separated, e.g. docker-hub-rate-limit,acr-pull-perms): " TAGS_RAW
[[ -z "$TAGS_RAW" ]] && { echo "ERROR: at least one tag required" >&2; exit 1; }
# Build a YAML list
TAGS_YAML=$(echo "$TAGS_RAW" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | awk 'NF { print "  - " $0 }')

read -rp "Severity (low | medium | high): " SEVERITY
case "$SEVERITY" in
  low|medium|high) ;;
  *) echo "ERROR: severity must be low | medium | high" >&2; exit 1 ;;
esac

DATE=$(date +%Y-%m-%d)
FILE="$LEARNINGS_DIR/${DATE}_${PROJECT}.md"

if [[ -f "$FILE" ]]; then
  echo "File already exists: $FILE — opening to append."
else
  cat > "$FILE" <<EOF
---
project: ${PROJECT}
date: ${DATE}
issues:
${TAGS_YAML}
severity: ${SEVERITY}
promoted: false
---

# Session Learnings — ${PROJECT}

## Issue 1 — <short description>

### What happened
<symptom you observed>

### Root cause
<why it happened>

### Fix applied
<what you changed; include file:line refs>

Files changed:
- \`path/to/file.ts:42\`

Status: ⏳ Not yet promoted to gotchas
EOF
  echo "Created: $FILE"
fi

# Open in $EDITOR or fall back to common editors
EDITOR_CMD="${EDITOR:-${VISUAL:-}}"
if [[ -z "$EDITOR_CMD" ]]; then
  if command -v code >/dev/null 2>&1; then
    EDITOR_CMD="code"
  elif command -v nano >/dev/null 2>&1; then
    EDITOR_CMD="nano"
  elif command -v vim >/dev/null 2>&1; then
    EDITOR_CMD="vim"
  fi
fi

if [[ -n "$EDITOR_CMD" ]]; then
  echo "Opening in $EDITOR_CMD..."
  exec $EDITOR_CMD "$FILE"
else
  echo "No editor found. Edit manually: $FILE"
fi
