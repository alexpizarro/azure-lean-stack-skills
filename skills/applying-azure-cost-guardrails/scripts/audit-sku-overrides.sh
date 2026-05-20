#!/usr/bin/env bash
# Audits a Bicep tree for fixed-cost SKUs and missing cost guardrails.
# Run on every PR that touches infra/.
#
# Usage: bash audit-sku-overrides.sh [path]    (default: infra/)
#
# Exit code: 0 if only WARN/INFO; non-zero if any FAIL.

set -uo pipefail

TARGET="${1:-infra/}"

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: directory not found: $TARGET" >&2
  exit 2
fi

# Counters
fail_count=0
warn_count=0

# Helper: report a finding
report() {
  local level="$1"   # FAIL | WARN | INFO
  local file="$2"
  local line="$3"
  local msg="$4"
  printf "[%s] %s:%s — %s\n" "$level" "$file" "$line" "$msg"
  case "$level" in
    FAIL) fail_count=$((fail_count + 1)) ;;
    WARN) warn_count=$((warn_count + 1)) ;;
  esac
}

# Scan helper
scan() {
  local pattern="$1"
  local level="$2"
  local msg="$3"
  while IFS=: read -r file line _; do
    [[ -z "$file" ]] && continue
    report "$level" "$file" "$line" "$msg"
  done < <(grep -RInE "$pattern" "$TARGET" 2>/dev/null)
}

echo "─── Azure cost guardrail audit: $TARGET ───"
echo ""

# --- FAIL: always-on App Service Plans ---
scan "name:\s*'(B[1-3]|S[1-3]|P[1-3]V[2-4])'" \
  "FAIL" \
  "Fixed-cost App Service Plan SKU detected — bills 24/7, even idle"

# --- FAIL: Premium Functions Plan ---
scan "name:\s*'EP[1-3]'" \
  "FAIL" \
  "Premium Functions Plan (EP) — bills 24/7. Use Y1 (Consumption) or FC1 (Flex) instead"

# --- FAIL: Dedicated ACA workload profile ---
scan "workloadProfileType:\s*'(D[0-9]+|E[0-9]+|NC[0-9]+)" \
  "FAIL" \
  "Dedicated ACA workload profile — bills per-minute even idle. Use 'Consumption'"

# --- FAIL: minReplicas > 0 without comment ---
# (heuristic — true if minReplicas: 1+ is set; reviewer must verify justification)
while IFS=: read -r file line content; do
  [[ -z "$file" ]] && continue
  # Skip if a comment on the same line or the line above mentions cold start / always warm / SLA
  if ! awk -v ln="$line" 'NR>=ln-1 && NR<=ln { print }' "$file" | grep -qiE "cold\s*start|always.warm|SLA|justif"; then
    report "WARN" "$file" "$line" "minReplicas > 0 — confirm cold start matters (add a comment if intentional)"
  fi
done < <(grep -RInE "minReplicas:\s*[1-9]" "$TARGET" 2>/dev/null)

# --- WARN: GRS / RAGRS storage ---
scan "name:\s*'Standard_(GRS|RAGRS|GZRS|RAGZRS)'" \
  "WARN" \
  "Geo-redundant storage — ~2× cost. Verify DR requirement is documented"

# --- WARN: Premium storage ---
scan "name:\s*'Premium_(LRS|ZRS)'" \
  "WARN" \
  "Premium storage — ~10× cost of Standard. Confirm IOPS requirement"

# --- WARN: provisioned SQL (non-serverless) ---
scan "name:\s*'GP_Gen5_[0-9]+'" \
  "WARN" \
  "Provisioned SQL — bills 24/7. Prefer GP_S_Gen5_N (Serverless) unless sustained traffic"

scan "tier:\s*'(BusinessCritical|Premium)'" \
  "WARN" \
  "SQL Premium/BC tier — bills 24/7. Justify the cost"

# --- INFO: missing dailyQuotaGb on Log Analytics ---
loga_files=$(grep -RIl "Microsoft.OperationalInsights/workspaces" "$TARGET" 2>/dev/null)
for f in $loga_files; do
  if ! grep -q "dailyQuotaGb" "$f"; then
    report "INFO" "$f" "0" "Log Analytics workspace without dailyQuotaGb cap — strongly recommended"
  fi
done

# --- INFO: missing lifecycle rules on storage ---
storage_files=$(grep -RIl "Microsoft.Storage/storageAccounts'@" "$TARGET" 2>/dev/null)
for f in $storage_files; do
  if ! grep -q "managementPolicies" "$f"; then
    report "INFO" "$f" "0" "Storage account without lifecycle rules — consider adding for cost ageing"
  fi
done

# --- INFO: API Management ---
if grep -RIqE "Microsoft.ApiManagement/service" "$TARGET" 2>/dev/null; then
  loc=$(grep -RInE "Microsoft.ApiManagement/service" "$TARGET" | head -1)
  report "WARN" "${loc%%:*}" "${loc#*:}" "API Management detected — Developer tier ~$50/mo, Standard ~$700/mo"
fi

# --- Summary ---
echo ""
echo "─── Summary ───"
echo "FAIL: $fail_count"
echo "WARN: $warn_count"
echo ""

if (( fail_count > 0 )); then
  echo "Review the FAIL findings before merging."
  exit 1
fi

if (( warn_count > 0 )); then
  echo "WARN findings — verify intent before merging."
fi

exit 0
