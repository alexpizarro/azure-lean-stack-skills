#!/usr/bin/env bash
# Sets all 6 GitHub Actions secrets needed by the deploy workflows.
#
# Reads from /tmp/azure-oidc-vars.sh (written by create-sp-with-oidc.sh +
# generate-sql-password.sh) OR from environment variables you set yourself.

set -euo pipefail

if [[ -f /tmp/azure-oidc-vars.sh ]]; then
  # shellcheck disable=SC1091
  source /tmp/azure-oidc-vars.sh
fi

: "${AZURE_TENANT_ID:?AZURE_TENANT_ID required}"
: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID required}"
: "${AZURE_CLIENT_ID_TEST:?AZURE_CLIENT_ID_TEST required}"
: "${AZURE_CLIENT_ID_PROD:?AZURE_CLIENT_ID_PROD required}"
: "${SQL_ADMIN_PASSWORD_TEST:?SQL_ADMIN_PASSWORD_TEST required}"
: "${SQL_ADMIN_PASSWORD_PROD:?SQL_ADMIN_PASSWORD_PROD required}"

echo "Setting 6 GitHub Actions secrets via gh CLI..."

gh secret set AZURE_TENANT_ID         --body "$AZURE_TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID   --body "$AZURE_SUBSCRIPTION_ID"
gh secret set AZURE_CLIENT_ID_TEST    --body "$AZURE_CLIENT_ID_TEST"
gh secret set AZURE_CLIENT_ID_PROD    --body "$AZURE_CLIENT_ID_PROD"
gh secret set SQL_ADMIN_PASSWORD_TEST --body "$SQL_ADMIN_PASSWORD_TEST"
gh secret set SQL_ADMIN_PASSWORD_PROD --body "$SQL_ADMIN_PASSWORD_PROD"

echo ""
echo "Verifying..."
gh secret list | grep -E "AZURE_|SQL_ADMIN_PASSWORD_"

# Clean up the temp file containing passwords
rm -f /tmp/azure-oidc-vars.sh
echo ""
echo "✓ Done. Cleaned up /tmp/azure-oidc-vars.sh"
