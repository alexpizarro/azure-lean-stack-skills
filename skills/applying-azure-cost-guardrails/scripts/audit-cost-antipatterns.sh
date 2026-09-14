#!/usr/bin/env bash
# Audits APP SOURCE (not just Bicep) for Guardrail-#11 cost anti-patterns that
# defeat scale-to-zero — the kind that caused a real serverless-SQL overrun.
#
# Detects:
#   1. health/status/ping/keepalive endpoints that run a DB query (keeps SQL
#      Serverless awake on every poll)                              — Guardrail #11
#   2. frequent schedulers (Logic App Recurrence / cron <= 15 min) that may be
#      pointed at a DB-backed endpoint                              — Guardrail #11
#   3. cooldownPeriod > 300s ("the second minReplicas")             — Guardrail #12b
#   4. setInterval UI polling without a tab-visibility gate          — Guardrail #12a
#   5. anonymous health endpoint probing a downstream service        — Guardrail #12a
#   6. deploy workflows that update / health-curl a Container App    — Guardrail #13
#
# Usage: bash audit-cost-antipatterns.sh [path]    (default: .)
# Exit:  non-zero if any [WARN] findings (so it can gate CI).

set -uo pipefail
TARGET="${1:-.}"

warn_count=0
report() {  # level file line msg
  printf "[%s] %s:%s — %s\n" "$1" "$2" "$3" "$4"
  [ "$1" = "WARN" ] && warn_count=$((warn_count + 1))
}

echo "─── Cost anti-pattern audit (Guardrail #11): $TARGET ───"
echo ""

# Where app source lives. Default to api/ but scan src/ too if present.
SRC_DIRS=()
for d in api src functions; do
  [ -d "$TARGET/$d" ] && SRC_DIRS+=("$TARGET/$d")
done
[ ${#SRC_DIRS[@]} -eq 0 ] && SRC_DIRS=("$TARGET")

# Skip build output and vendored deps — only first-party source matters.
# .claude/worktrees holds throwaway agent copies of the repo — scanning them
# reports the same finding N times and drowns the real ones. output/ and data/
# can hold GB of pipeline JSON in a data project; grepping it hangs the audit.
EXCLUDE_RE='/(node_modules|dist|dist-test|out|build|\.next|coverage|\.claude/worktrees|\.git|__pycache__|venv|\.venv)/'
# Bulk data dirs, anchored to the repo root only — a nested api/data/ with real
# Bicep still gets scanned.
EXCLUDE_RE="${EXCLUDE_RE}|^${TARGET%/}/(output|releases)/"

# grep --exclude-dir PRUNES the walk; filtering grep's output does not — grep has
# already opened every file by then. A data-bearing repo can hold GB of pipeline
# JSON (measured: 9.2 GB / 29,872 files in one real project), which made this
# audit appear to hang. Prune at traversal time.
PRUNE=(--exclude-dir=node_modules --exclude-dir=dist --exclude-dir=dist-test
       --exclude-dir=out --exclude-dir=build --exclude-dir=.next
       --exclude-dir=coverage --exclude-dir=.git --exclude-dir=__pycache__
       --exclude-dir=venv --exclude-dir=.venv --exclude-dir=worktrees
       --exclude-dir=output --exclude-dir=releases --exclude-dir=archive)

# This script necessarily *contains* the patterns it greps for. Skip itself so a
# run against the plugin repo doesn't report its own detector source.
SELF_RE="audit-cost-antipatterns\.sh"

# ── 1. health/status endpoints that touch the DB ───────────────────────────
# Find candidate endpoint files by name, then check for DB access inside.
db_re='getPool|\.query\(|\bquery<|mssql|SELECT |fromSql|prisma\.|drizzle|knex\(|pg\.|new Pool\('
name_re='health|status|ping|keepalive|keep-alive|warmup|heartbeat|liveness|readiness'

while IFS= read -r f; do
  [ -z "$f" ] && continue
  # The file is name-matched; now find the first DB-access line for the pointer
  # (skipping import/require lines — importing getPool is not calling it).
  line=$(grep -nEi "$db_re" "$f" 2>/dev/null | grep -vE "^[0-9]+:\s*(import\b|const .*= require\()" | head -1 | cut -d: -f1)
  # Mitigated only if the DB access sits INSIDE an explicit opt-in branch: the file must
  # read a `deep` / `probe` query flag AND the first DB access must come after that read.
  if [ -n "$line" ]; then
    gate=$(grep -nEi "query\.get\(['\"](deep|probe)['\"]\)|searchParams\.get\(['\"](deep|probe)['\"]\)|\?(deep|probe)=" "$f" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$gate" ] && [ "$gate" -lt "$line" ]; then
      line=""
    fi
  fi
  if [ -n "$line" ]; then
    report "WARN" "$f" "$line" "health/status endpoint queries the DB — keeps SQL Serverless awake on every poll. Make /health DB-free; gate the DB check behind ?deep=1 (Guardrail #11)."
  fi
done < <(find "${SRC_DIRS[@]}" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.cs" \) 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE" \
           | grep -iE "/($name_re)[^/]*\.(ts|js|py|cs)$" )

# ── 2. frequent schedulers (Recurrence interval <= 15 min) ─────────────────
# Logic App Bicep / definitions: frequency Minute AND an interval of 1–15 within the
# next few lines (a 30- or 60-minute Minute-recurrence is fine).
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  interval=$(sed -n "${line},$((line+6))p" "$f" 2>/dev/null | grep -oEi "interval['\"]?\s*[:=]\s*[0-9]+" | grep -oE "[0-9]+" | head -1)
  if [ -n "$interval" ] && [ "$interval" -le 15 ]; then
    report "WARN" "$f" "$line" "scheduler every ${interval} min. If it targets a DB-backed endpoint it keeps SQL Serverless awake. Point it at a DB-free endpoint, or use flat Basic tier (Guardrail #11)."
  fi
done < <(grep "${PRUNE[@]}" -rInE "frequency['\"]?\s*[:=]\s*['\"]Minute['\"]" "$TARGET" \
           --include="*.bicep" --include="*.json" --include="*.sh" 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE")

# cron expressions running every minute / few minutes (e.g. "*/5 * * * *", "* * * * *")
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  report "WARN" "$f" "$line" "sub-15-min cron schedule. If it hits a DB-backed endpoint it keeps SQL Serverless awake (Guardrail #11)."
done < <(grep "${PRUNE[@]}" -rInE "(^|['\"[:space:]])(\*|\*/[1-9]|\*/1[0-5])\s+\*\s+\*\s+\*\s+\*(['\"[:space:]]|$)|cronExpression['\"]?\s*[:=]\s*['\"](\*|\*/[1-9])" "$TARGET" \
           --include="*.bicep" --include="*.json" --include="*.sh" --include="*.yml" --include="*.yaml" 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE")

# ── 3. cooldownPeriod > 300s — "the second minReplicas" (Guardrail #12b) ───
# If cooldown exceeds mean inter-arrival time the alive window never closes and
# a minReplicas:0 app is pinned 24/7. Proven: 7200s cooldown billed ~A$2/day to
# serve 26 requests per 8 hours.
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  val=$(printf '%s' "$rest" | grep -oE '[0-9]+' | tail -1)
  if [ -n "$val" ] && [ "$val" -gt 300 ] 2>/dev/null; then
    report "WARN" "$f" "$line" "cooldownPeriod: ${val}s (> 300s default). If this exceeds mean inter-arrival time the app NEVER scales to zero despite minReplicas:0 — functionally minReplicas:1 but invisible (Guardrail #12b)."
  fi
done < <(grep "${PRUNE[@]}" -rInE "cooldownPeriod['\"]?\s*[:=]" "$TARGET" \
           --include="*.bicep" --include="*.json" --include="*.yml" --include="*.yaml" --include="*.sh" 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE")

# ── 4. UI interval-polling a service (Guardrail #12a) ──────────────────────
# setInterval(..., <=60s) polling an upstream URL = 2,880 hits/day PER OPEN TAB,
# and keeps polling in a backgrounded tab unless visibility-gated.
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  # Only flag when the file has no visibility gating at all.
  if ! grep -qE "visibilityState|hidden|useVisibility|document\.visibility" "$f" 2>/dev/null; then
    report "WARN" "$f" "$line" "setInterval polling without a tab-visibility gate — 2,880 hits/day per open tab keeps a scale-to-zero container awake. Gate on document.visibilityState, or make the probe on-demand (Guardrail #12a)."
  fi
done < <(grep "${PRUNE[@]}" -rInE "setInterval\([^)]*,\s*(([1-9]|[1-5][0-9])000|[0-9]{1,4})\s*\)" "$TARGET" \
           --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE")

# ── 5. anonymous health endpoint probing a DOWNSTREAM service (#12a) ───────
# Distinct from check 1 (DB): waking another service on every anonymous request.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  line=$(grep -nEi 'checkEnrichment|fetch\(|axios\.|httpClient|HttpClient|requests\.get' "$f" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$line" ] && continue
  # An anonymous route is fine IF the downstream probe is opt-in and gated.
  # Treat "?probe=" opt-in or an auth/admin check as sufficient mitigation.
  if ! grep -qEi "isAdmin|requireAuth|authorize|getUser|x-api-key|bearer|probe=" "$f" 2>/dev/null; then
    report "WARN" "$f" "$line" "health/status endpoint calls a downstream service and appears unauthenticated — every bot, uptime check and deploy smoke test wakes it. Make the probe opt-in (?probe=x) AND admin-only; use a three-state healthy:true|false|null (Guardrail #12a)."
  fi
done < <(find "${SRC_DIRS[@]}" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.cs" \) 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE" \
           | grep -iE "/($name_re)[^/]*\.(ts|js|py|cs)$" )

# ── 6b. explicit denylist: names of resources you have retired ─────────────
# RETIRED_RESOURCES="trg-enrichment-aca my-old-app" bash audit-cost-antipatterns.sh .
# Any workflow/script that still mentions one of these is a FAIL-grade WARN.
for name in ${RETIRED_RESOURCES:-}; do
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
    report "WARN" "$f" "$line" "references RETIRED resource '$name' — CI will recreate / re-wake it on the next deploy (Guardrail #13, gotcha #43)."
  done < <(grep "${PRUNE[@]}" -rInF -- "$name" "$TARGET/.github" "$TARGET/scripts" "$TARGET/azure" "$TARGET/infra" 2>/dev/null \
             | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE")
done

# ── 6. CI resurrecting a retired resource (Guardrail #13) ──────────────────
# A deploy workflow that updates or health-curls an app you've retired will
# recreate and re-wake it on EVERY deploy. Proven: recurred twice this way.
if [ -d "$TARGET/.github/workflows" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
    report "WARN" "$f" "$line" "workflow updates or health-curls a Container App. If that app is retired this step either fails every deploy or re-wakes a billed replica — grep workflows for the resource name as part of retirement; verify deploys by asserting the image tag, never by curling a URL (Guardrail #13). Add the name to RETIRED_RESOURCES to make this a hard failure."
  done < <(grep "${PRUNE[@]}" -rInE "containerapp update|curl.*(/health|/api/status)" "$TARGET/.github/workflows" 2>/dev/null \
             | grep -ivE "$EXCLUDE_RE" | grep -vE "$SELF_RE")
fi

echo ""
echo "─── Summary ───"
echo "WARN: $warn_count"
if (( warn_count > 0 )); then
  echo ""
  echo "Review each finding. If the access is intentional and steady, switch the DB"
  echo "to flat Basic tier (~\$5/mo) — cheaper than kept-awake serverless. Otherwise"
  echo "decouple the poll from the DB (shallow health check / DB-free endpoint)."
  exit 1
fi
echo "No cost anti-patterns detected."
exit 0
