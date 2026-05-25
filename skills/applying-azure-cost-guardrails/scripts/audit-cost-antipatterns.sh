#!/usr/bin/env bash
# Audits APP SOURCE (not just Bicep) for Guardrail-#11 cost anti-patterns that
# defeat scale-to-zero — the kind that caused a real serverless-SQL overrun.
#
# Detects:
#   1. health/status/ping/keepalive endpoints that run a DB query (keeps SQL
#      Serverless awake on every poll)
#   2. frequent schedulers (Logic App Recurrence / cron <= 15 min) that may be
#      pointed at a DB-backed endpoint
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
EXCLUDE_RE='/(node_modules|dist|dist-test|out|build|\.next|coverage)/'

# ── 1. health/status endpoints that touch the DB ───────────────────────────
# Find candidate endpoint files by name, then check for DB access inside.
db_re='getPool|\.query\(|\bquery<|mssql|SELECT |fromSql|prisma\.|drizzle|knex\(|pg\.|new Pool\('
name_re='health|status|ping|keepalive|keep-alive|warmup|heartbeat|liveness|readiness'

while IFS= read -r f; do
  [ -z "$f" ] && continue
  # The file is name-matched; now find the first DB-access line for the pointer.
  line=$(grep -nEi "$db_re" "$f" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$line" ]; then
    report "WARN" "$f" "$line" "health/status endpoint queries the DB — keeps SQL Serverless awake on every poll. Make /health DB-free; gate the DB check behind ?deep=1 (Guardrail #11)."
  fi
done < <(find "${SRC_DIRS[@]}" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.cs" \) 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE" \
           | grep -iE "/($name_re)[^/]*\.(ts|js|py|cs)$" )

# ── 2. frequent schedulers (Recurrence interval <= 15 min) ─────────────────
# Logic App Bicep / definitions: look for frequency Minute with small interval.
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  report "WARN" "$f" "$line" "frequent scheduler (Minute cadence). If it targets a DB-backed endpoint it keeps SQL Serverless awake. Point it at a DB-free endpoint, or use flat Basic tier (Guardrail #11)."
done < <(grep -rInE "frequency['\"]?\s*[:=]\s*['\"]Minute['\"]" "$TARGET" \
           --include="*.bicep" --include="*.json" --include="*.sh" 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE")

# cron expressions running every minute / few minutes (e.g. "*/5 * * * *", "* * * * *")
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  f="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  report "WARN" "$f" "$line" "sub-15-min cron schedule. If it hits a DB-backed endpoint it keeps SQL Serverless awake (Guardrail #11)."
done < <(grep -rInE "(\*/[1-9]|\*/1[0-5])\s+\*\s+\*\s+\*\s+\*|cronExpression['\"]?\s*[:=]\s*['\"]\*/[1-9]" "$TARGET" \
           --include="*.bicep" --include="*.json" --include="*.sh" --include="*.yml" --include="*.yaml" 2>/dev/null \
           | grep -ivE "$EXCLUDE_RE")

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
