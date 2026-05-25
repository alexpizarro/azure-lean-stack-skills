---
name: developing-azure-apps-locally
description: Runs an Azure Lean Stack app fully offline on localhost — API + SQL Server + blob storage — with no Azure dependency, as the "try" tier of the local→test→prod flow on the main branch. Provides a docker-compose stack (SQL Server 2022 + Azurite), a one-command bootstrap, mock-mode for unset service keys, and an optional seed-from-test path. Use when setting up local development, running the app offline before deploying, adding a local database/blob emulator, or onboarding a developer to the repo.
---

# Developing Azure Apps Locally

Run the whole app on `localhost` — API + SQL + blob storage — with **no dependency on Azure**. This is the local "try" tier of the deployment model: **local (`main`) → `test` → `production`**.

`main` is never connected to an Azure environment. You iterate locally against an offline stack, then promote to `test` (and later `production`) via the branch-per-environment flow. See [orchestrating-azure-deployments](../orchestrating-azure-deployments/SKILL.md) Architecture Decision #0.

## When to use which local mode

| Mode | Command | Use for |
|------|---------|---------|
| **Fully offline** (this skill) | `bash scripts/up.sh` then `npm start` + `npm run dev` | Backend work, schema changes, fast iteration, no Azure cost |
| **Frontend against live test backend** | `cd frontend && npm run dev:test` | UI-only work that needs real test data; no local API/SQL |

Prefer fully-offline for anything touching the API, SQL, or storage.

## The offline stack

- **SQL Server 2022** in Docker (`mcr.microsoft.com/mssql/server:2022-latest`) — the same engine Azure SQL is built on. "Serverless" is an Azure *compute tier*, not a local concept; the T-SQL engine is identical, so migrations and queries behave the same locally as in Azure.
- **Azurite** (`mcr.microsoft.com/azure-storage/azurite`) — local Azure Blob emulator. Blobs stream from `http://127.0.0.1:10000` instead of Azure Storage.

Both run from [templates/docker-compose.yml](templates/docker-compose.yml).

> **Apple Silicon:** the SQL Server image is amd64. Enable Docker Desktop → Settings → General → **"Use Rosetta for x86/amd64 emulation"**. (Azure SQL Edge was retired 2025-09 and dropped arm64, so `mssql/server` under Rosetta is the supported high-fidelity choice.)

## Workflow checklist

Copy this into your response and tick items off:

```
Local dev setup:
- [ ] Step 1: Docker Desktop running (Rosetta enabled on Apple Silicon)
- [ ] Step 2: Copy templates/docker-compose.yml to repo root, templates/local.settings.json.example to api/local.settings.json
- [ ] Step 3: Run scripts/up.sh — starts SQL + Azurite, applies migrations, sets Azurite CORS
- [ ] Step 4: (optional) Run scripts/seed-from-test.sh to copy a small dataset from the test env
- [ ] Step 5: cd api && npm start   (Functions host on http://localhost:7071)
- [ ] Step 6: cd frontend && npm run dev   (Vite on http://localhost:5173, proxies /api → 7071)
- [ ] Step 7: Verify the app loads and a DB-backed page returns data
```

## One-command bootstrap

```bash
bash scripts/up.sh
```

This: `docker compose up -d` → applies all `infra/sql/migrations/*.sql` to a local database → (optionally) seeds data → sets Azurite blob CORS for `localhost:5173`. Then in two terminals:

```bash
cd api && npm start          # Azure Functions host → http://localhost:7071
cd frontend && npm run dev   # Vite → http://localhost:5173 (proxies /api → 7071)
```

## Config — `api/local.settings.json`

Copy [templates/local.settings.json.example](templates/local.settings.json.example) to `api/local.settings.json`. It is preconfigured for the offline stack:

- `SQL_CONNECTION_STRING` → local Docker SQL (`localhost,1433`, `sa` / `LocalDev_Pass123!`)
- `STORAGE_CONNECTION_STRING` → the Azurite well-known dev connection string
- Dev `JWT_SECRET` / `ADMIN_API_KEY` placeholders
- **All external-service keys left empty → mock mode.** Functions check `if (!process.env.KEY)` and return a mock response (e.g. email runs in mock mode locally). This is the same empty-string + `__HINT_*` convention from [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md).

Never put real Azure credentials in `local.settings.json` — the offline stack doesn't need them.

## Individual scripts

| Script | Purpose |
|--------|---------|
| [scripts/up.sh](scripts/up.sh) | Full bootstrap: compose up → migrate → (seed) → CORS |
| [scripts/migrate.sh](scripts/migrate.sh) | (Re)apply `infra/sql/migrations/*.sql` to local SQL — idempotent |
| [scripts/seed-from-test.sh](scripts/seed-from-test.sh) | Optional: copy a small dataset from the test env into local SQL + Azurite |
| [scripts/cors.sh](scripts/cors.sh) | Set Azurite blob CORS for `localhost:5173` (SAS / Range / `crossOrigin` reads) |

`migrate.sh` reuses the same migration files the CI workflow runs. The local SQL Server install of `sqlcmd` is assumed present; for the CI install dance see [managing-azure-sql-migrations](../managing-azure-sql-migrations/SKILL.md).

## Reset / stop

```bash
docker compose down       # stop containers, keep data
docker compose down -v    # stop AND wipe the local DB + blobs
```

## Why local fidelity matters

The offline stack runs the *same* T-SQL engine and the *same* migration files as Azure, and Azurite speaks the real Blob API. A migration or query that works locally works in test. The only deliberate differences:

- **Compute tier** — serverless auto-pause is an Azure billing behaviour with no local equivalent (and irrelevant locally). See [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) for how the tier choice affects cost in Azure.
- **SAS URLs are endpoint-aware** — Azurite is path-style `http://127.0.0.1:10000/devstoreaccount1/...`, Azure is `https://{account}.blob.core.windows.net/...`. Don't hard-code the Azure host; derive it from the storage client.

## Composes with

- [orchestrating-azure-deployments](../orchestrating-azure-deployments/SKILL.md) — the local→test→prod branch model (Decision #0)
- [managing-azure-sql-migrations](../managing-azure-sql-migrations/SKILL.md) — same migration files, applied locally
- [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md) — the mock-mode + `local.settings.json` convention, vite `/api` proxy
- [optimizing-azure-blob-storage-cost](../optimizing-azure-blob-storage-cost/SKILL.md) — the blob CORS rules `cors.sh` mirrors locally

## Reference

[references/offline-stack.md](references/offline-stack.md) — Rosetta/amd64 notes, endpoint-aware SAS URLs, mock mode, `dev:test` trade-off, troubleshooting.

**Proven in:** `bc-videohub-lite` (`docs/LOCAL-DEV.md`, `docker-compose.yml`, `scripts/local-dev/*`) — a full offline SQL + Azurite stack used as the `main`-branch dev tier.
