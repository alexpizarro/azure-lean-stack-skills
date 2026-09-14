---
name: deploying-azure-static-web-apps
description: Deploys React + Azure Functions apps to Azure Static Web Apps with managed API functions, including the CommonJS / index.ts import / route-registration gotchas that make new functions 404 silently. Provides the SWA Bicep module, staticwebapp.config.json routing + security headers, and the API entrypoint convention. Use when scaffolding a SWA-based project, adding a new API function, or fixing a deployed function that returns 404 even though it compiled successfully.
---

# Deploying Azure Static Web Apps

The default deployment target for React + Functions web apps. Free tier, global CDN, managed Functions baked in, zero ongoing cost when idle.

## When to use SWA vs FC1 vs Container Apps vs App Service

| Need | Use |
|------|-----|
| CRUD REST API, React frontend, HTTP-only, < 30s requests, build output < 250 MB per environment (500 MB total on Free) | **SWA managed functions** (this skill) |
| Timer triggers, queue triggers, AI workloads, > 30s execution, managed identity / Key Vault refs | [FC1 Flex Consumption](../deploying-fc1-flex-consumption-functions/SKILL.md) |
| Long-running server, WebSocket/SSE, custom Docker runtime, Next.js with middleware | [Container Apps](../deploying-azure-container-apps/SKILL.md) |
| Next.js ISR / SSR that outgrew SWA's **app-size ceiling** (250 MB/env Free, 500 MB/env Standard), always-on with no cold start | App Service **B1** (~US$13/mo/env; share the plan with a Function App). Proven: `trg-directory-website`. Not a pack skill yet — a deliberate fixed-cost trade, documented in cost-guardrails "Known floors". |

SWA's Next.js hybrid (SSR) support is preview and breaks with middleware on Next ≥13.4; `BC-Quick Check In` (Next 16 + middleware) moved to Container Apps for that reason.

## Project structure

```
frontend/                        — React 19 + Vite 8 + TypeScript
├── src/
│   ├── App.tsx
│   └── services/api.ts
├── public/
│   └── staticwebapp.config.json — routing + security headers
├── vite.config.ts               — proxy /api/* → localhost:7071 (or the test SWA via `npm run dev:test`)
└── package.json                 — scripts: dev, dev:test, typecheck, build

api/                              — Managed Azure Functions v4 (Node 22)
├── src/
│   ├── index.ts                 — Entry point — IMPORT EVERY FUNCTION FILE HERE
│   ├── functions/
│   │   ├── health.ts            — shallow /api/health (DB-free); ?deep=1 probes SQL
│   │   ├── hello.ts             — app.http(...) at the bottom registers the route
│   │   ├── getItems.ts
│   │   └── createItem.ts
│   └── lib/
│       └── database.ts          — mssql pool, module-level singleton
├── host.json
├── tsconfig.json                — "module": "commonjs" required for SWA
├── package.json                 — "main": "dist/index.js", "engines": {"node":"22"}, "typecheck" script
└── local.settings.json.example  — empty strings + __HINT_* keys
```

## The four SWA gotchas you WILL hit

### 1. New function returns 404 — forgot to import in `index.ts`

```typescript
// api/src/index.ts — every function file imported as a side effect
import './functions/hello';
import './functions/getItems';
import './functions/createItem';
import './functions/newThing';    // ← add this when you create newThing.ts
```

The `app.http(...)` registration in each function file only runs when the module is loaded. If `index.ts` doesn't import it, the route silently doesn't exist. The TypeScript compiles fine. The deploy succeeds. The URL returns 404.

**Make this part of your "add a function" muscle memory:** create the file, write the function, **add the import**.

### 2. CommonJS, not ESM

SWA managed functions require:

```json
// api/tsconfig.json
{ "compilerOptions": { "module": "commonjs" } }

// api/package.json
{ "main": "dist/index.js" }      // ← specific path, not "dist/**/*.js"
// (do NOT add "type": "module")
```

Standalone FC1 apps use the **same** CommonJS shape (proven in `bc-videohub-lite`), so `api/` moves to FC1 unchanged.

### 3. Managed functions can't use managed identity or Key Vault references

SWA managed functions support **HTTP triggers only**, and neither managed identity nor `@Microsoft.KeyVault(...)` app-setting references. Secrets (the SQL connection string) live as plain SWA app settings. If a security review requires secretless auth, move `api/` to [FC1](../deploying-fc1-flex-consumption-functions/SKILL.md) and follow [securing-azure-sql-and-storage-with-managed-identity](../securing-azure-sql-and-storage-with-managed-identity/SKILL.md). Linking that Function App as a "bring your own" backend needs the **Standard** SWA plan (US$9/mo); on Free, the browser calls the Function App directly with CORS.

### 4. The SWA edge overwrites the `Authorization` header

Requests through `/api/*` arrive at your function with `Authorization` **replaced by the platform's own token** (proven with a header-echo function in `count8-website`). API keys and bearer tokens must travel in a custom header (e.g. `x-api-key`). If a caller is cut over to SWA, switch its header *before* DNS moves.

## Node version

`platform.apiRuntime` in `staticwebapp.config.json` pins the managed-functions runtime. `node:22` is the newest supported value (Node 20 support in Azure Functions ended 2026-04-30; `node:24` is not yet accepted for managed functions). Match it with `"engines": { "node": "22" }` in `api/package.json` and an `.nvmrc` of `22` so Oryx, CI and local dev agree.

## Function file template

```typescript
// api/src/functions/getItems.ts
import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { query } from '../lib/database';

export async function getItems(req: HttpRequest, ctx: InvocationContext): Promise<HttpResponseInit> {
  // Mock when DB not configured (local dev convenience)
  if (!process.env.SQL_CONNECTION_STRING) {
    ctx.warn('SQL_CONNECTION_STRING not set — returning mock');
    return { status: 200, jsonBody: { items: [{ id: 1, name: '[MOCK] Item' }] } };
  }

  const items = await query<{ Id: number; Name: string }>('SELECT Id, Name FROM dbo.Items');
  return { status: 200, jsonBody: { items } };
}

// Route registration — runs when this module is imported by index.ts
app.http('getItems', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'items',
  handler: getItems,
});
```

## `local.settings.json.example` pattern

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_EXTENSION_VERSION": "~4",
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "SQL_CONNECTION_STRING": "",
    "__HINT_SQL_CONNECTION_STRING": "Server=tcp:{org}-{project}-sql-test.database.windows.net,1433;Database={org}-{project}-sqldb-test;User Id=sqladmin;Password=YOUR_PASSWORD;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  }
}
```

**Use `""` for all user-input values.** Placeholder strings like `"sk-YOUR_KEY"` are truthy in JavaScript and fool `if (!value)` checks, causing confusing runtime errors instead of clean "not configured" mocks. Use `__HINT_*` keys for format documentation (Functions ignores `__`-prefixed keys).

## Mock pattern

Always check the env var; fall back to a mock when not set. This makes local dev work without provisioning:

```typescript
if (!process.env.AI_PROJECT_ENDPOINT) {
  ctx.warn('AI_PROJECT_ENDPOINT not set — returning mock response');
  return { status: 200, jsonBody: { result: '[MOCK] Set AI_PROJECT_ENDPOINT.' } };
}

if (process.env.SQL_CONNECTION_STRING) {
  await saveToDB(...);
} else {
  ctx.warn('SQL_CONNECTION_STRING not set — skipping DB write');
}
```

For a full offline stack (real local SQL + blob storage, not just mocks), use [developing-azure-apps-locally](../developing-azure-apps-locally/SKILL.md) — a Docker SQL Server 2022 + Azurite stack with a one-command bootstrap. Mock mode (above) covers external services you don't want to run locally (AI, email); the offline stack covers the DB + storage your app actually needs.

## Shallow health check (avoid a costly anti-pattern)

If you add a health/status endpoint, make the default check **DB-free** — return `200` without querying the database. A health endpoint that runs a DB query on every call, combined with any uptime monitor or scheduler polling it, keeps a SQL Serverless database permanently awake and bills compute 24/7 (see [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) Guardrail #11).

```typescript
// GET /api/health — shallow, DB-free. Safe to poll frequently.
export async function health(req: HttpRequest): Promise<HttpResponseInit> {
  const deep = req.query.get('deep') === '1';
  if (!deep) {
    return { status: 200, jsonBody: { ok: true } };   // no DB call — won't wake serverless
  }
  // Deep check runs the DB query only on explicit request (e.g. a manual probe).
  try {
    await getPool();
    return { status: 200, jsonBody: { ok: true, db: 'ok' } };
  } catch (e) {
    return { status: 503, jsonBody: { ok: false, db: 'error' } };
  }
}
app.http('health', { methods: ['GET'], authLevel: 'anonymous', route: 'health', handler: health });
```

Point uptime monitors and schedulers at `/api/health` (shallow); reserve `/api/health?deep=1` for on-demand diagnostics. The template ships this as `api/src/functions/health.ts`. Proven: `trg-directory-website`'s `status.ts` queried the DB on every call and a 5-min scheduler hit it, defeating auto-pause.

## `staticwebapp.config.json`

```json
{
  "platform": { "apiRuntime": "node:22" },
  "navigationFallback": { "rewrite": "/index.html", "exclude": ["/api/*", "/assets/*", "*.{css,js,png,svg,jpg,jpeg,ico,woff2}"] },
  "globalHeaders": {
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=()"
  }
}
```

Don't add a catch-all `"route": "/*"` rewrite — `navigationFallback` already does that, and the legacy catch-all is only for migrating from the deprecated `routes.json`.

See [references/swa-config.md](references/swa-config.md) for the full routing + auth pattern.

## Bicep

The SWA Bicep module lives in [`scaffolding-azure-bicep-infrastructure/templates/infra/modules/staticWebApp.bicep`](../scaffolding-azure-bicep-infrastructure/templates/infra/modules/staticWebApp.bicep). It exposes:

- `skuName` — per-env (`Free` in test, `Standard` in prod)
- `sqlConnectionString` — `@secure()`, sets the `SQL_CONNECTION_STRING` app setting

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — generates the SWA Bicep + workflow
- [managing-azure-sql-migrations](../managing-azure-sql-migrations/SKILL.md) — for the DB schema
- [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) — when functions 404 or return 500
