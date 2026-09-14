#!/usr/bin/env bash
# Generates Azure SQL admin passwords that meet the complexity requirements:
# min 8 chars, uppercase + lowercase + digit + symbol. 20 chars here.
#
# Uses python3's `secrets` module (present on macOS and every GitHub runner) rather
# than `tr | head` (SIGPIPE under `pipefail`) or `shuf` (not on macOS).
#
# Outputs values for the GitHub secret step. Writes them to /tmp for sibling scripts.

set -euo pipefail

gen_password() {
  python3 - <<'PY'
import secrets, string
U, L, D, S = string.ascii_uppercase, string.ascii_lowercase, string.digits, "!@#%^*"
chars = [secrets.choice(U) for _ in range(4)] + [secrets.choice(L) for _ in range(4)] \
      + [secrets.choice(D) for _ in range(4)] + [secrets.choice(S) for _ in range(2)] \
      + [secrets.choice(U + L + D) for _ in range(6)]
# Fisher-Yates with a CSPRNG so the character classes aren't predictably positioned
for i in range(len(chars) - 1, 0, -1):
    j = secrets.randbelow(i + 1)
    chars[i], chars[j] = chars[j], chars[i]
print("".join(chars))
PY
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

# Persist for sibling scripts (owner-only file — contains secrets)
umask 077
cat >> /tmp/azure-oidc-vars.sh <<EOF
export SQL_ADMIN_PASSWORD_TEST="$SQL_PASSWORD_TEST"
export SQL_ADMIN_PASSWORD_PROD="$SQL_PASSWORD_PROD"
EOF
chmod 600 /tmp/azure-oidc-vars.sh
echo "Wrote SQL passwords to /tmp/azure-oidc-vars.sh"
