#!/usr/bin/env bash
# Runs all infra/sql/migrations/*.sql files in alphabetical order against
# Azure SQL. Manages a temporary firewall rule for the runner's IP and
# guarantees cleanup on exit via trap.
#
# Required env vars:
#   SQL_SERVER       — fully qualified server name (xxx.database.windows.net)
#   SQL_DB           — database name
#   SQL_PASSWORD     — admin password (from GitHub secret)
#   RG               — resource group containing the SQL server
# Optional env vars:
#   SQL_USER         — admin login (default: sqladmin)
#   MIGRATIONS_DIR   — path to migrations (default: infra/sql/migrations)

set -euo pipefail

: "${SQL_SERVER:?SQL_SERVER required (e.g. mysrv.database.windows.net)}"
: "${SQL_DB:?SQL_DB required}"
: "${SQL_PASSWORD:?SQL_PASSWORD required}"
: "${RG:?RG required (resource group of the SQL server)}"

SQL_USER="${SQL_USER:-sqladmin}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-infra/sql/migrations}"
SQL_SERVER_NAME="${SQL_SERVER/.database.windows.net/}"
RULE_NAME="github-runner-${GITHUB_RUN_ID:-$(date +%s)}"
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

# Guarantee firewall rule removal on exit, even if a migration fails
trap '
  echo "Cleaning up firewall rule..."
  az sql server firewall-rule delete \
    --resource-group "$RG" \
    --server "$SQL_SERVER_NAME" \
    --name "$RULE_NAME" \
    --yes 2>/dev/null || true
' EXIT

# Verify sqlcmd is installed
if [[ ! -x "$SQLCMD" ]]; then
  echo "ERROR: sqlcmd not found at $SQLCMD. Run install-sqlcmd.sh first." >&2
  exit 1
fi

# Add runner IP to SQL firewall
RUNNER_IP=$(curl -s https://api.ipify.org)
echo "Adding firewall rule '$RULE_NAME' for $RUNNER_IP..."
az sql server firewall-rule create \
  --resource-group "$RG" \
  --server "$SQL_SERVER_NAME" \
  --name "$RULE_NAME" \
  --start-ip-address "$RUNNER_IP" \
  --end-ip-address "$RUNNER_IP" \
  --output none

# Run all migrations in alphabetical order
shopt -s nullglob
files=("$MIGRATIONS_DIR"/*.sql)
if (( ${#files[@]} == 0 )); then
  echo "No migration files in $MIGRATIONS_DIR — nothing to do."
  exit 0
fi

for f in $(printf '%s\n' "${files[@]}" | sort); do
  echo "Running migration: $f"
  "$SQLCMD" -S "$SQL_SERVER" -d "$SQL_DB" \
    -U "$SQL_USER" -P "$SQL_PASSWORD" \
    -i "$f" -C
done

echo "✓ All migrations completed successfully."
