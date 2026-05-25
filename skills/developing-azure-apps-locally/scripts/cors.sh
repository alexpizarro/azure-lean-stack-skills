#!/usr/bin/env bash
# Set blob CORS on the local Azurite emulator so the browser can fetch blobs
# with crossOrigin="anonymous" (needed for Range reads, Web Audio, canvas image
# reads, etc.). Without it Azurite returns no Access-Control-Allow-Origin header
# and the fetch is blocked. Idempotent — safe to re-run.
#
# Mirrors the CORS rules the deployed Azure storage account carries
# (see optimizing-azure-blob-storage-cost/references/cors-for-spa.md).
set -euo pipefail

# Well-known Azurite dev connection string (public dev account+key — safe to commit).
AZURITE_CS="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"

# Use an isolated az config dir if your machine hosts multiple Azure subscriptions,
# so this never mutates the shared/global Azure context.
export AZURE_CONFIG_DIR="${AZURE_CONFIG_DIR:-$HOME/.azure}"

echo "==> Setting Azurite blob CORS (localhost dev origins) ..."
az storage cors clear --services b --connection-string "$AZURITE_CS" -o none 2>/dev/null || true
az storage cors add \
  --services b \
  --methods GET HEAD OPTIONS PUT \
  --origins "http://localhost:5173" "http://127.0.0.1:5173" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600 \
  --connection-string "$AZURITE_CS" -o none
echo "    Azurite CORS set for http://localhost:5173"

# Create the containers your app expects (idempotent). Adjust the list per project.
for c in ${LOCAL_CONTAINERS:-"uploads"}; do
  az storage container create --name "$c" --connection-string "$AZURITE_CS" -o none
  echo "    container '$c' ready"
done
