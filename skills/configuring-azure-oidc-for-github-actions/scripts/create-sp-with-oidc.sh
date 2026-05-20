#!/usr/bin/env bash
# Creates two service principals (test + prod) with OIDC federated credentials
# for branch-scoped GitHub Actions deployments.
#
# Idempotent: safe to re-run. Existing SPs are detected by displayName.
#
# Required env vars: ORG, PROJECT, GITHUB_ORG, REPO
# Optional env vars: AZURE_CONFIG_DIR (for multi-subscription isolation)

set -euo pipefail

: "${ORG:?ORG required (e.g. acme)}"
: "${PROJECT:?PROJECT required (e.g. taskapp)}"
: "${GITHUB_ORG:?GITHUB_ORG required (e.g. myorg)}"
: "${REPO:?REPO required (e.g. taskapp)}"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Subscription: $SUBSCRIPTION_ID"
echo "Tenant:       $TENANT_ID"
echo "Repo:         $GITHUB_ORG/$REPO"
echo ""

create_sp() {
  local env="$1"   # test | prod
  local sp_name="${ORG}-${PROJECT}-github-${env}"
  local branch="$env"
  [[ "$env" == "prod" ]] && branch="production"

  echo "── ${env} environment ──────────────────────────────────────"

  # Reuse existing SP if present (by displayName)
  local client_id
  client_id=$(az ad sp list --display-name "$sp_name" --query '[0].appId' -o tsv 2>/dev/null || echo "")

  if [[ -n "$client_id" ]]; then
    echo "SP already exists: $sp_name (appId: $client_id)"
  else
    echo "Creating SP: $sp_name"
    client_id=$(az ad sp create-for-rbac \
      --name "$sp_name" \
      --role "Contributor" \
      --scopes "/subscriptions/$SUBSCRIPTION_ID" \
      --query appId -o tsv 2>/dev/null)
    echo "Created SP appId: $client_id"
  fi

  # Federated credential (branch-scoped)
  local cred_name="github-${env}-branch"
  local subject="repo:${GITHUB_ORG}/${REPO}:ref:refs/heads/${branch}"

  if az ad app federated-credential list --id "$client_id" --query "[?name=='$cred_name']" -o tsv 2>/dev/null | grep -q .; then
    echo "Federated credential '$cred_name' already exists. Verifying subject..."
    local existing_subject
    existing_subject=$(az ad app federated-credential list --id "$client_id" \
      --query "[?name=='$cred_name'].subject | [0]" -o tsv)
    if [[ "$existing_subject" != "$subject" ]]; then
      echo "WARNING: subject mismatch."
      echo "  Expected: $subject"
      echo "  Actual:   $existing_subject"
      echo "  → AADSTS70021 will occur. Fix manually with: az ad app federated-credential update"
    fi
  else
    echo "Adding federated credential: $cred_name (subject: $subject)"
    az ad app federated-credential create \
      --id "$client_id" \
      --parameters "{
        \"name\": \"$cred_name\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"$subject\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }" > /dev/null
  fi

  # Export for the parent script to pick up
  if [[ "$env" == "test" ]]; then
    export CLIENT_ID_TEST="$client_id"
  else
    export CLIENT_ID_PROD="$client_id"
  fi
  echo "✓ ${env}: client_id=$client_id"
  echo ""
}

create_sp test
create_sp prod

cat <<EOF
─────────────────────────────────────────────────────────────────
Summary — save these values for the GitHub secret step:
  AZURE_TENANT_ID         = $TENANT_ID
  AZURE_SUBSCRIPTION_ID   = $SUBSCRIPTION_ID
  AZURE_CLIENT_ID_TEST    = $CLIENT_ID_TEST
  AZURE_CLIENT_ID_PROD    = $CLIENT_ID_PROD
─────────────────────────────────────────────────────────────────
EOF

# Persist for sibling scripts in the same shell session
cat > /tmp/azure-oidc-vars.sh <<EOF
export AZURE_TENANT_ID="$TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export AZURE_CLIENT_ID_TEST="$CLIENT_ID_TEST"
export AZURE_CLIENT_ID_PROD="$CLIENT_ID_PROD"
EOF
echo "Wrote /tmp/azure-oidc-vars.sh for sibling scripts."
