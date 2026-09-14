# Stack versions

Canonical versions used by every scaffolded project. Bump these centrally; sub-skills inherit.

**Last verified: 2026-09-14** (npm registry, GitHub releases, Microsoft Learn, `az provider show`).

| Technology | Version | Notes |
|------------|---------|-------|
| Node.js | **22 LTS** | Both SWA managed functions and FC1. Node 20 support in Azure Functions **ended 2026-04-30**. Node 24 is GA on Flex Consumption and SWA-linked apps but **not yet an `apiRuntime` value for SWA managed functions** (`node:22` is the newest). Node 22 is LTS until 2027-04. |
| React | 19.x (`^19.3.0`) | |
| TypeScript | 5.x (`^5.9.3`) | TypeScript 6/7 exist but the Vite + Functions toolchain is proven on 5.9. |
| Vite | **8.x** (`^8.3.0`) | Needs Node `^20.19 \|\| >=22.12`. `@vitejs/plugin-react` `^6.1.1` (v6 requires Vite 8). |
| `@azure/functions` | `^4.16.2` | Functions SDK v4 (programming model v4). Engines `node >=20`. |
| `mssql` | **`^12.7.2`** | v12 breaking change: the library **no longer clones config objects** — treat a config as read-only after `sql.connect()`. tedious 19/20 under the hood. |
| `@types/mssql` | **`^12.3.0`** | Still required — mssql v12 doesn't ship its own `.d.ts`. Match the major. |
| `@azure/identity` | `^4.13.2` | Only when using managed identity for SQL/Blob. Engines `node >=22`. |
| `@azure/storage-blob` | `^12.33.0` | Engines `node >=22`. |
| Bicep | latest (0.47.x) | `az bicep upgrade` in CI. The `az`-bundled compiler lags the standalone release by a few versions — pick API versions that have types in both (see table below). |
| GitHub Actions runner | `ubuntu-latest` | = ubuntu-24.04 today; ubuntu-26.04 is in public preview. The sqlcmd installer derives the apt line from `lsb_release`, so it survives the move. |
| `actions/checkout` | **v6** | v5+ run on Node 24. Node 20 actions are removed from runners on **2026-09-23** — v4 will stop working. |
| `actions/setup-node` | **v6** | Same Node 24 requirement. |
| `azure/login` | **v3** | Node 24 runtime; same `client-id` / `tenant-id` / `subscription-id` OIDC inputs as v2. v2 (Node 20) dies with the 2026-09-23 runner change. |
| `Azure/static-web-apps-deploy` | v1 | Docker-based action (unaffected by the Node 20 removal). Builds Functions + React together via Oryx. |
| `Azure/functions-action` | **avoid** | The repo was disabled on GitHub 2026-06-05 → 2026-06-10 and every FC1 deploy broke. Use `az functionapp deployment source config-zip` (see `deploying-fc1-flex-consumption-functions`). |
| `mcr.microsoft.com/mssql/server` | `2022-latest` | amd64 only; Rosetta on Apple Silicon. `2025-latest` RTM crashes under Docker Desktop's emulation (AVX); CU1+ fixes it. Stay on 2022 for local dev. |
| `mcr.microsoft.com/azure-storage/azurite` | `3.37.0` | Pin it — the pack's own rule is "never `:latest`". |
| Azure CLI | 2.83+ | `az ad sp create-for-rbac --sdk-auth` is deprecated (`--json-auth` replaces it; OIDC needs neither). |

## Bicep API versions (stable, typed in the `az`-bundled Bicep 0.41 AND standalone 0.47)

| Resource type | Use | Newest ARM-registered stable (may lack Bicep types) |
|---|---|---|
| `Microsoft.Resources/resourceGroups` | `2024-03-01` | 2023-07-01 is the newest the provider lists; 2024-03-01 is accepted by ARM and typed |
| `Microsoft.Web/staticSites` (+`/config`) | `2024-04-01` | 2025-05-01 (no types in 0.41) |
| `Microsoft.Web/serverfarms`, `sites`, `sites/config` | `2024-04-01` | 2025-03-01 typed; 2026-07-15 registered |
| `Microsoft.Sql/servers` (+`/databases`, `/firewallRules`) | `2023-08-01` | 2025-01-01 (no types in 0.41) |
| `Microsoft.Storage/storageAccounts` (+ children) | `2024-01-01` | 2026-06-01 registered; 2025-01-01 typed |
| `Microsoft.App/containerApps`, `jobs`, `managedEnvironments` | `2025-01-01` | 2025-07-01 typed; 2026-01-01 registered |
| `Microsoft.OperationalInsights/workspaces` | `2025-02-01` | 2026-03-01 registered |
| `Microsoft.Insights/components` | `2020-02-02` | still current |
| `Microsoft.Insights/metricAlerts` | `2018-03-01` | 2026-01-01 registered, no types in 0.41 |
| `Microsoft.Insights/actionGroups` | `2023-01-01` | newer are all `-preview` |
| `Microsoft.Communication/*` | `2025-09-01` | 2026-03-18 registered, no types in 0.41 |
| `Microsoft.Consumption/budgets` | `2024-08-01` | 2026-06-01 registered |
| `Microsoft.Logic/workflows` | `2019-05-01` | still current |
| `Microsoft.Authorization/roleAssignments` | `2022-04-01` | still current |
| `Microsoft.CostManagement/query` (REST) | `api-version=2024-08-01` | 2026-08-01 registered |

Rule: prefer the newest **stable** version that compiles without `BCP081` in the `az`-bundled Bicep. Re-check with `az provider show --namespace <ns> --query "resourceTypes[?resourceType=='<type>'].apiVersions"`.

## Required `api/package.json` shape (SWA managed functions)

```json
{
  "name": "{org}-{project}-api",
  "version": "1.0.0",
  "main": "dist/index.js",
  "engines": { "node": "22" },
  "scripts": {
    "build": "tsc",
    "typecheck": "tsc --noEmit",
    "prestart": "npm run build",
    "start": "func start"
  },
  "dependencies": {
    "@azure/functions": "^4.16.2",
    "mssql": "^12.7.2"
  },
  "devDependencies": {
    "@types/mssql": "^12.3.0",
    "@types/node": "^22.20.0",
    "typescript": "^5.9.3"
  }
}
```

`typecheck` is required — `pr-checks.yml` runs `npm run typecheck` in both `frontend/` and `api/`.

## TypeScript module setting

| Runtime | `tsconfig.json` "module" | `package.json` "type" |
|---------|-------------------------|----------------------|
| SWA managed functions | `commonjs` | (omit) |
| FC1 Flex Consumption (standalone) | `commonjs` (proven) | (omit) |

**CommonJS is the proven shape on both.** The earlier "FC1 = ESM" rule came from the v1 starter and no shipping project uses it; `bc-videohub-lite`'s FC1 API is CommonJS with `"main": "dist/index.js"`. Azure Functions' `"type": "module"` support is still preview-grade (`.mjs` only). Stay on CommonJS unless a dependency forces ESM.

`"main": "dist/index.js"` — must be a concrete file path. Glob patterns like `"dist/functions/*.js"` are not resolved by the Functions host.

## `@types/*` rule

When adding any npm package, check whether `@types/{package}` is required. Packages that ship their own `.d.ts` files (e.g. `@azure/functions`, `@azure/identity`) don't need it; CommonJS libraries (e.g. `mssql`) usually do. Missing types cause `TS7016` at build time.

## Region defaults

| Service | Default region |
|---------|---------------|
| Resource Group, SQL, Storage, ACA, FC1 | `australiaeast` (Flex Consumption is available in `australiaeast` and `australiasoutheast`) |
| Static Web App | `eastasia` (only supported SWA region nearest AU) |
| ACS Email | `'global'` (literal — not a real Azure region) |
| ACS `dataLocation` | `'Australia'` (plain English, not `australiaeast`) |
