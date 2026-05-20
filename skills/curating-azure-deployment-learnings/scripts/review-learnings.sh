#!/usr/bin/env bash
# Scan learnings/ for issue tags. Group by tag, report severity + count,
# and recommend whether to promote into the gotcha catalogue.

set -uo pipefail

LEARNINGS_DIR="${LEARNINGS_DIR:-learnings}"
GOTCHAS_FILE="${GOTCHAS_FILE:-skills/diagnosing-azure-deployment-failures/references/gotchas.md}"

if [[ ! -d "$LEARNINGS_DIR" ]]; then
  echo "No learnings/ directory at $LEARNINGS_DIR" >&2
  exit 1
fi

# Extract (issue_tag, severity, project, promoted) from each learning file's frontmatter.
# python3 makes the YAML parse robust.
python3 - "$LEARNINGS_DIR" "$GOTCHAS_FILE" <<'PYEOF'
import os, re, sys, json

learnings_dir = sys.argv[1]
gotchas_file = sys.argv[2]

# Read gotchas file once — used to check if a tag is already documented.
gotchas_text = ""
if os.path.exists(gotchas_file):
    with open(gotchas_file) as f:
        gotchas_text = f.read().lower()

def parse_frontmatter(text):
    m = re.match(r'^---\s*\n(.*?)\n---', text, re.S)
    if not m:
        return {}
    fm = {}
    current_key = None
    for line in m.group(1).splitlines():
        line = line.rstrip()
        if not line:
            continue
        if line.startswith('  - ') and current_key == 'issues':
            fm.setdefault('issues', []).append(line[4:].strip())
        elif ':' in line and not line.startswith(' '):
            k, _, v = line.partition(':')
            k, v = k.strip(), v.strip()
            current_key = k
            if v:
                fm[k] = v
            else:
                fm[k] = []
    return fm

# Aggregate
agg = {}  # tag -> {severity, projects:set, any_promoted:bool}

for fname in sorted(os.listdir(learnings_dir)):
    if not fname.endswith('.md'):
        continue
    if fname == 'README.md':
        continue
    path = os.path.join(learnings_dir, fname)
    with open(path) as f:
        fm = parse_frontmatter(f.read())
    if not fm or 'issues' not in fm:
        continue
    project = fm.get('project', fname)
    severity = fm.get('severity', 'unknown')
    promoted = str(fm.get('promoted', 'false')).lower() == 'true'
    for tag in fm.get('issues', []):
        a = agg.setdefault(tag, {'severity': severity, 'projects': set(), 'promoted': False})
        a['projects'].add(project)
        # Track highest severity seen
        order = {'low': 0, 'medium': 1, 'high': 2, 'unknown': -1}
        if order.get(severity, -1) > order.get(a['severity'], -1):
            a['severity'] = severity
        if promoted:
            a['promoted'] = True

# Render report
if not agg:
    print("No tagged learnings found.")
    sys.exit(0)

print(f"{'Issue tag':<40} | {'Severity':<8} | {'Projects':>8} | Status")
print('-' * 80)

def status_for(tag, a):
    if a['promoted']:
        return 'already promoted'
    if tag.lower() in gotchas_text:
        return 'already in gotchas'
    if a['severity'] == 'high':
        return 'PROMOTE'
    if a['severity'] == 'medium' and len(a['projects']) >= 2:
        return 'PROMOTE'
    if a['severity'] == 'medium':
        return 'wait for 2nd project'
    return 'skip (low)'

for tag in sorted(agg.keys(),
                  key=lambda t: (-{'low':0,'medium':1,'high':2,'unknown':-1}.get(agg[t]['severity'], -1),
                                 -len(agg[t]['projects']))):
    a = agg[tag]
    print(f"{tag[:40]:<40} | {a['severity']:<8} | {len(a['projects']):>8} | {status_for(tag, a)}")
PYEOF
