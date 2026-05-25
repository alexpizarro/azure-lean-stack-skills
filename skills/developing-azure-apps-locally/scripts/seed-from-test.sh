#!/usr/bin/env bash
# OPTIONAL: seed the local DB + Azurite with a small dataset from the TEST env.
# Skeleton — adapt the table list and blob containers to your schema.
#
# Pattern (proven in bc-videohub-lite/scripts/local-dev/seed-from-test.sh):
#   1. temp firewall rule on the test SQL server (removed on exit via trap)
#   2. copy a bounded set of rows (FK-safe order) from test SQL into local SQL
#   3. copy the matching blobs from test storage into Azurite
#
# Required env:
#   TEST_RG            test resource group (e.g. acme-taskapp-rg-test)
#   TEST_SQL_SERVER    test SQL server name (without .database.windows.net)
#   TEST_STORAGE       test storage account name
#   TEST_SQL_PASSWORD  test sqladmin password
# Optional env:
#   AZURE_CONFIG_DIR   isolated az config dir for multi-subscription machines
#   ROW_LIMIT          cap rows per table (default 50)
set -euo pipefail

: "${TEST_RG:?TEST_RG required}"
: "${TEST_SQL_SERVER:?TEST_SQL_SERVER required}"
: "${TEST_STORAGE:?TEST_STORAGE required}"
: "${TEST_SQL_PASSWORD:?TEST_SQL_PASSWORD required}"

export AZURE_CONFIG_DIR="${AZURE_CONFIG_DIR:-$HOME/.azure}"
SA_PASS="${MSSQL_SA_PASSWORD:-LocalDev_Pass123!}"
LOCAL_DB="${LOCAL_DB:-${PROJECT:-appdb}}"
ROW_LIMIT="${ROW_LIMIT:-50}"
AZURITE_CS="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"

# 1) temp firewall on test SQL for this machine
IP=$(curl -s ifconfig.me)
echo "==> Adding temp firewall rule on $TEST_SQL_SERVER for $IP ..."
az sql server firewall-rule create -g "$TEST_RG" -s "$TEST_SQL_SERVER" \
  --name "temp-localseed" --start-ip-address "$IP" --end-ip-address "$IP" -o none 2>/dev/null || true
cleanup() { az sql server firewall-rule delete -g "$TEST_RG" -s "$TEST_SQL_SERVER" --name "temp-localseed" -o none 2>/dev/null || true; }
trap cleanup EXIT

# 2) SQL rows — adapt to your schema. Example: copy the 'items' table.
#    For FK-heavy schemas, write a small Node script using mssql (see bc-videohub
#    seed-from-test.cjs) that selects parents before children.
echo "==> (adapt this section to your tables) Example: copy 'items' (top $ROW_LIMIT)"
echo "    Use bcp / sqlcmd / a Node mssql script to read from test and INSERT into local [$LOCAL_DB]."
echo "    Skipping by default — no generic schema to copy."

# 3) blobs: test storage -> Azurite (best-effort, per container)
KEY=$(az storage account keys list -g "$TEST_RG" -n "$TEST_STORAGE" --query "[0].value" -o tsv)
TMP=$(mktemp -d)
for c in ${SEED_CONTAINERS:-"uploads"}; do
  echo "==> Copying blobs from container '$c' into Azurite ..."
  mkdir -p "$TMP/$c"
  az storage container create --name "$c" --connection-string "$AZURITE_CS" -o none
  az storage blob download-batch -d "$TMP/$c" -s "$c" \
    --account-name "$TEST_STORAGE" --account-key "$KEY" -o none 2>/dev/null || true
  if [ -n "$(ls -A "$TMP/$c" 2>/dev/null)" ]; then
    az storage blob upload-batch -d "$c" -s "$TMP/$c" --connection-string "$AZURITE_CS" --overwrite -o none
  else
    echo "   (no blobs in '$c')"
  fi
done
rm -rf "$TMP"
echo "✓ Seed complete (blobs copied; adapt the SQL section to your schema)."
