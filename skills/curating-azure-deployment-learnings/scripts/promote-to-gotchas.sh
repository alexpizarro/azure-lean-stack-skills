#!/usr/bin/env bash
# Given an issue tag, find all learnings mentioning it and emit a draft
# markdown table row for inclusion in gotchas.md.
#
# Usage: bash promote-to-gotchas.sh <issue-tag>

set -uo pipefail

TAG="${1:?Usage: $0 <issue-tag>}"
LEARNINGS_DIR="${LEARNINGS_DIR:-learnings}"

python3 - "$LEARNINGS_DIR" "$TAG" <<'PYEOF'
import os, re, sys

learnings_dir = sys.argv[1]
target_tag = sys.argv[2]

matches = []

for fname in sorted(os.listdir(learnings_dir)):
    if not fname.endswith('.md') or fname == 'README.md':
        continue
    path = os.path.join(learnings_dir, fname)
    with open(path) as f:
        text = f.read()
    m = re.match(r'^---\s*\n(.*?)\n---', text, re.S)
    if not m:
        continue
    fm_text = m.group(1)
    if f"- {target_tag}" not in fm_text:
        continue
    project_m = re.search(r'^project:\s*(.+)$', fm_text, re.M)
    severity_m = re.search(r'^severity:\s*(.+)$', fm_text, re.M)
    project = project_m.group(1).strip() if project_m else fname
    severity = severity_m.group(1).strip() if severity_m else 'unknown'
    matches.append({'file': fname, 'project': project, 'severity': severity})

if not matches:
    print(f"No learnings tagged with '{target_tag}'", file=sys.stderr)
    sys.exit(1)

print(f"Tag: {target_tag}")
print(f"Found in {len(matches)} learning(s):")
for m in matches:
    print(f"  - {m['project']} ({m['severity']}) — {m['file']}")
print()
print("Suggested gotcha row (edit to add the row number and fill in the columns):")
print("")
print("| N | <Symptom> | <Root cause> | <Fix> |")
print("|---|-----------|--------------|-------|")
print()
print("Edit gotchas.md to insert under the most relevant category.")
print("Then update each learning's frontmatter:  promoted: true")
print("And the Status line:  Status: ✅ Promoted to gotcha #N in commit {sha}")
PYEOF
