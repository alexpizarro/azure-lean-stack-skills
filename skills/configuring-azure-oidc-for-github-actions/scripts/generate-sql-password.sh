#!/usr/bin/env bash
# Generates Azure SQL admin passwords that meet the complexity requirements:
# min 8 chars, uppercase + lowercase + digit + symbol.
#
# Outputs values for the GitHub secret step. Writes them to /tmp for sibling scripts.

set -euo pipefail

# Force at least one of each character class to guarantee complexity
gen_password() {
  local upper lower digit symbol rest
  upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 4)
  lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 4)
  digit=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 4)
  symbol=$(LC_ALL=C tr -dc '!@#%^*' < /dev/urandom | head -c 2)
  rest=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 6)

  # Shuffle so the character classes aren't predictably positioned
  echo "${upper}${lower}${digit}${symbol}${rest}" | fold -w1 | shuf | tr -d '\n'
}

SQL_PASSWORD_TEST=$(gen_password)
SQL_PASSWORD_PROD=$(gen_password)

cat <<EOF
─────────────────────────────────────────────────────────────────
SQL admin passwords (set as GitHub secrets):
  SQL_ADMIN_PASSWORD_TEST = $SQL_PASSWORD_TEST
  SQL_ADMIN_PASSWORD_PROD = $SQL_PASSWORD_PROD

Store these somewhere safe (1Password, etc.) — they're not recoverable.
─────────────────────────────────────────────────────────────────
EOF

# Persist for sibling scripts
cat >> /tmp/azure-oidc-vars.sh <<EOF
export SQL_ADMIN_PASSWORD_TEST="$SQL_PASSWORD_TEST"
export SQL_ADMIN_PASSWORD_PROD="$SQL_PASSWORD_PROD"
EOF
echo "Wrote SQL passwords to /tmp/azure-oidc-vars.sh"
