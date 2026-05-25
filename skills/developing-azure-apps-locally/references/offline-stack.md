# Offline stack reference

Details for running the fully-offline local dev stack (SQL Server 2022 + Azurite).

## Contents
- Apple Silicon / amd64 notes
- Azurite endpoint-aware SAS URLs
- Mock mode for unset keys
- `dev:test` vs offline trade-off
- Troubleshooting

## Apple Silicon / amd64

The SQL Server 2022 image (`mcr.microsoft.com/mssql/server:2022-latest`) is amd64-only. On Apple Silicon:

1. Docker Desktop → Settings → General → enable **"Use Rosetta for x86/amd64 emulation"**.
2. The `docker-compose.yml` pins `platform: linux/amd64` so compose doesn't try (and fail) to pull an arm64 variant.

Azure SQL Edge (the old arm64-friendly option) was retired 2025-09 and dropped arm64 support, so `mssql/server` under Rosetta is the supported, high-fidelity local engine. It is the *same* engine Azure SQL is built on — "serverless" is an Azure compute/billing tier, not a separate engine, so T-SQL behaviour is identical.

## Azurite endpoint-aware SAS URLs

Azurite is path-style and HTTP:

```
http://127.0.0.1:10000/devstoreaccount1/{container}/{blob}
```

Azure Storage is subdomain-style and HTTPS:

```
https://{account}.blob.core.windows.net/{container}/{blob}
```

**Never hard-code `*.blob.core.windows.net`** when generating URLs or SAS tokens. Derive the endpoint from the storage client / connection string so the same code produces correct URLs locally and in Azure. The Azure SDK's `BlobServiceClient` built from the connection string already does this — use `containerClient.getBlockBlobClient(name).url` and the generated SAS helpers rather than string-concatenating a host.

## Mock mode for unset keys

`api/local.settings.json` leaves external-service keys empty. Functions check the env var and fall back to a mock:

```typescript
if (!process.env.ACS_CONNECTION_STRING) {
  ctx.warn('ACS not configured — email running in mock mode');
  return { ok: true, mock: true };
}
```

This lets the whole app run offline without provisioning ACS, AI, etc. The same empty-string + `__HINT_*` convention is documented in [deploying-azure-static-web-apps](../../deploying-azure-static-web-apps/SKILL.md). Real Azure credentials must never be placed in `local.settings.json`.

## `dev:test` vs fully-offline

Add a `dev:test` script to `frontend/package.json` that points Vite at the deployed test SWA:

```json
{
  "scripts": {
    "dev": "vite",
    "dev:test": "vite --mode test"
  }
}
```

With a `.env.test` setting the API base URL to the test SWA hostname. Use `dev:test` only for UI work that needs live test data; it does NOT run a local API or DB. For anything touching the API, SQL, or storage, use the fully-offline stack — it's faster and incurs no Azure cost.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `docker compose up` pulls forever / fails on arm64 | Rosetta not enabled | Enable Docker Desktop → Use Rosetta for x86/amd64 |
| `migrate.sh`: "SQL Server not reachable" | Container still starting | Wait for the healthcheck; the script retries 40× at 3s |
| Browser blocks blob fetch (CORS) | Azurite CORS not set | Re-run `scripts/cors.sh` (also auto-run by `up.sh`) |
| Blob URLs point at `*.blob.core.windows.net` locally | Hard-coded Azure host | Derive the URL from the storage client, not a string literal |
| `sqlcmd: command not found` on host | mssql-tools not installed locally | `migrate.sh` auto-falls back to running sqlcmd inside the SQL container |
| Functions return real errors instead of mocks | A key is set to a non-empty placeholder | Use `""` for unset keys — non-empty strings are truthy and skip the mock branch |
| Reset everything | Stale local data | `docker compose down -v` (wipes the DB + blobs), then `bash scripts/up.sh` |

## Why local fidelity matters

A migration or query that works against the local SQL Server 2022 container works against Azure SQL — same engine, same migration files (`infra/sql/migrations/*.sql`) the CI workflow runs. Azurite speaks the real Blob REST API. The only deliberate differences are the storage endpoint shape (above) and the Azure-only serverless auto-pause billing behaviour (irrelevant locally; see [applying-azure-cost-guardrails](../../applying-azure-cost-guardrails/SKILL.md)).
