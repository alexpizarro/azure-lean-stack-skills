#!/usr/bin/env bash
# One-command bootstrap for the fully-offline local dev stack.
#   docker compose up  ->  migrate  ->  (optional seed)  ->  Azurite CORS
#
# Run from the repo root (where docker-compose.yml lives), or it will cd there.
# Set SEED=1 to also run seed-from-test.sh (requires Azure sign-in to the test env).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# If this script was copied into the project, ROOT is the project root.
# If still inside the skill, fall back to the current working directory.
[ -f "$ROOT/docker-compose.yml" ] || ROOT="$(pwd)"
cd "$ROOT"

echo "==> Starting local stack (SQL Server 2022 + Azurite) ..."
docker compose up -d

bash "$(dirname "${BASH_SOURCE[0]}")/migrate.sh"

if [ "${SEED:-0}" = "1" ]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/seed-from-test.sh"
fi

bash "$(dirname "${BASH_SOURCE[0]}")/cors.sh"

cat <<'EOF'

✓ Local dev stack ready (fully offline).
    API:      cd api && npm start          # http://localhost:7071
    Frontend: cd frontend && npm run dev   # http://localhost:5173 (proxies /api -> 7071)

  Stop:  docker compose down        (add -v to also wipe the DB + blobs)
  Seed:  SEED=1 bash scripts/up.sh  (copies a small dataset from the test env)
EOF
