# Stack versions

Canonical versions used by every scaffolded project. Bump these centrally; sub-skills inherit.

| Technology | Version | Notes |
|------------|---------|-------|
| React | 19.x | |
| TypeScript | 5.x | |
| Vite | 6.x | |
| `@azure/functions` | ^4.5.0 | Functions SDK v4 (programming model v4) |
| Node.js | 22 LTS | Both SWA managed functions and FC1 |
| `mssql` | ^11.0.1 | |
| `@types/mssql` | ^9.1.5 | **Required** — mssql v11 doesn't ship its own `.d.ts` |
| Bicep | latest | Installed via `az bicep upgrade` in CI |
| GitHub Actions runner | `ubuntu-latest` | Currently ubuntu-24.04 |
| `azure/login` | v2 | OIDC support |
| `Azure/static-web-apps-deploy` | v1 | Builds Functions + React together via Oryx |
| `Azure/functions-action` | v1.5.2+ | Minimum version that supports FC1 detection |

## Required `api/package.json` shape

```json
{
  "name": "{org}-{project}-api",
  "version": "1.0.0",
  "main": "dist/index.js",
  "engines": { "node": "22" },
  "scripts": {
    "build": "tsc",
    "start": "npm run build && func start"
  },
  "dependencies": {
    "@azure/functions": "^4.5.0",
    "mssql": "^11.0.1"
  },
  "devDependencies": {
    "@types/mssql": "^9.1.5",
    "@types/node": "^22.0.0",
    "typescript": "^5.7.3"
  }
}
```

## TypeScript module setting differs by runtime

| Runtime | `tsconfig.json` "module" | `package.json` "type" |
|---------|-------------------------|----------------------|
| SWA managed functions | `commonjs` | (omit) |
| FC1 Flex Consumption (standalone) | `ES2022` | `module` |

`"main": "dist/index.js"` — must be a concrete file path. Glob patterns like `"dist/functions/*.js"` are not resolved by the Functions host.

## `@types/*` rule

When adding any npm package, check whether `@types/{package}` is required. Packages that ship their own `.d.ts` files (e.g. `@azure/functions`) don't need it; CommonJS libraries (e.g. `mssql`) usually do. Missing types cause `TS7016` at build time.

## Region defaults

| Service | Default region |
|---------|---------------|
| Resource Group, SQL, Storage, ACA | `australiaeast` |
| Static Web App | `eastasia` (only supported SWA region nearest AU) |
| ACS Email | `'global'` (literal — not a real Azure region) |
| ACS `dataLocation` | `'Australia'` (plain English, not `australiaeast`) |
