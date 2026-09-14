#!/usr/bin/env bash
# Live check: is any Container App in the subscription(s) silently pinned at > 0 replicas?
# Config proves nothing — this reads RUNNING REPLICAS (not revisions: a revision stays
# "active" for months at zero replicas, and a revision-based check produced 6/6 false
# positives in a real estate). Guardrail #12 / gotchas #41–#43, #51.
#
# Usage: bash check-live-replicas.sh [subscription-id ...]   (default: every enabled subscription)
# Exit:  0 = every app at 0 replicas with sane config
#        1 = at least one app needs a look (running replicas / cooldown > 300 / minReplicas > 0)
#        2 = could not check (an az query failed — RBAC gap, expired login, throttling).
#            A broken check must never read as "all clear".
set -uo pipefail

SUBS=("$@")
if (( ${#SUBS[@]} == 0 )); then
  # while-read (not mapfile) so this runs on macOS's stock bash 3.2 too
  while IFS= read -r sub; do [ -n "$sub" ] && SUBS+=("$sub"); done \
    < <(az account list --query "[?state=='Enabled'].id" -o tsv) || true
  (( ${#SUBS[@]} > 0 )) || { echo "ERROR: az account list returned nothing — run az login" >&2; exit 2; }
fi

found=0; errors=0
azq() { # az … ; prints output, returns az's exit code, records failures
  local out; if out=$(az "$@" 2>/tmp/check-live-replicas.err); then printf '%s' "$out"; else
    errors=$((errors+1)); printf '[ERR]   az %s: %s\n' "$*" "$(tail -1 /tmp/check-live-replicas.err)" >&2; return 1; fi
}

for SUB in "${SUBS[@]}"; do
  apps=$(azq containerapp list --subscription "$SUB" --query "[].[name,resourceGroup]" -o tsv) || continue
  while IFS=$'\t' read -r N G; do
    [ -z "$N" ] && continue
    COOL=$(azq containerapp show -n "$N" -g "$G" --subscription "$SUB" \
             --query "properties.template.scale.cooldownPeriod" -o tsv) || continue
    MINR=$(azq containerapp show -n "$N" -g "$G" --subscription "$SUB" \
             --query "properties.template.scale.minReplicas" -o tsv) || continue
    # Sum running replicas across ALL active revisions (Multiple-revision apps can hold
    # several older revisions active at 0% traffic — each one can pin a replica).
    revs=$(azq containerapp revision list -n "$N" -g "$G" --subscription "$SUB" --all \
             --query "[?properties.active].name" -o tsv) || continue
    REPS=0; ok=1
    while IFS= read -r REV; do
      [ -z "$REV" ] && continue
      c=$(azq containerapp replica list -n "$N" -g "$G" --subscription "$SUB" --revision "$REV" \
            --query "length(@)" -o tsv) || { ok=0; break; }
      REPS=$((REPS + ${c:-0}))
    done <<< "$revs"
    [ "$ok" = 1 ] || continue
    flag=""
    [ "${COOL:-300}" -gt 300 ] 2>/dev/null && flag="${flag} cooldown=${COOL}s"
    [ "${MINR:-0}" -gt 0 ] 2>/dev/null && flag="${flag} minReplicas=${MINR}"
    [ "$REPS" -gt 0 ] && flag="${flag} RUNNING=${REPS}"
    if [ -n "$flag" ]; then
      printf "[CHECK] %s/%s (%s):%s\n" "$G" "$N" "${SUB:0:8}" "$flag"; found=$((found+1))
    else
      printf "[ok]    %s/%s (%s): 0 replicas, cooldown=%ss\n" "$G" "$N" "${SUB:0:8}" "${COOL:-300}"
    fi
  done <<< "$apps"
done

echo ""
echo "Apps needing a look: $found   Query errors: $errors"
echo "For each [CHECK] ask, in order: (1) what is calling it? (gotcha #41)  (2) is cooldown > inter-arrival time? (#42)  (3) does CI wake it? (#43)  (4) is a replica stuck Activating on ImagePullFailure? (#51)"
echo "Then prove any fix in BILLING, not config — Guardrail #14."
(( errors > 0 )) && { echo "Some queries failed — result is INDETERMINATE, not clean." >&2; exit 2; }
(( found > 0 )) && exit 1 || exit 0
