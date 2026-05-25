#!/usr/bin/env bash
# Apply all infra/sql/migrations/*.sql to the local Docker SQL Server.
# Mirrors the CI run-migrations loop (managing-azure-sql-migrations/scripts/run-migrations.sh).
# Idempotent — every migration from 002 onward self-guards via dbo.__MigrationHistory.
#
# Env overrides:
#   MSSQL_SA_PASSWORD  (default LocalDev_Pass123!)
#   LOCAL_DB           database name (default: derive from $PROJECT or "appdb")
#   LOCAL_SQL_SERVER   (default localhost,1433)
set -euo pipefail

SA_PASS="${MSSQL_SA_PASSWORD:-LocalDev_Pass123!}"
DB="${LOCAL_DB:-${PROJECT:-appdb}}"
SERVER="${LOCAL_SQL_SERVER:-localhost,1433}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$ROOT/infra/sql/migrations" ] || ROOT="$(pwd)"

# Resolve sqlcmd: prefer a host install, fall back to running inside the SQL container.
if command -v sqlcmd >/dev/null 2>&1; then
  run_sql() { sqlcmd -S "$SERVER" -U sa -P "$SA_PASS" -C "$@"; }
else
  echo "Note: host sqlcmd not found — running sqlcmd inside the SQL container."
  CID="$(docker compose ps -q sql 2>/dev/null || true)"
  [ -n "$CID" ] || { echo "ERROR: SQL container not running. Run 'docker compose up -d' first."; exit 1; }
  run_sql() { docker exec -i "$CID" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASS" -C "$@"; }
fi

echo "Waiting for SQL Server at $SERVER ..."
ok=
for _ in $(seq 1 40); do
  if run_sql -l 3 -Q "SELECT 1" >/dev/null 2>&1; then ok=1; break; fi
  sleep 3
done
[ -n "$ok" ] || { echo "ERROR: SQL Server not reachable"; exit 1; }

echo "Ensuring database [$DB] exists ..."
run_sql -Q "IF DB_ID('$DB') IS NULL CREATE DATABASE [$DB];"

echo "Applying migrations to [$DB] ..."
shopt -s nullglob
files=("$ROOT"/infra/sql/migrations/*.sql)
(( ${#files[@]} )) || { echo "No migration files found in infra/sql/migrations/"; exit 0; }
for f in $(printf '%s\n' "${files[@]}" | sort); do
  echo "  -> $(basename "$f")"
  # -i needs the file readable by the sqlcmd process; when running in-container,
  # pipe the file in via stdin instead of -i (path isn't mounted).
  if command -v sqlcmd >/dev/null 2>&1; then
    run_sql -b -d "$DB" -i "$f"
  else
    run_sql -b -d "$DB" < "$f"
  fi
done
echo "✓ Migrations applied to [$DB]."
