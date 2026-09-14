---
name: deploying-fc1-flex-consumption-functions
description: Deploys standalone Azure Function Apps on Flex Consumption (FC1) for workloads SWA managed functions can't handle — timer triggers, queue triggers, AI workloads, long-running operations, or when you need managed identity / Key Vault references (SWA managed functions support neither). Provisions via Bicep or ARM REST because az CLI flags silently fall back to the retiring Linux Consumption (Y1) plan. Includes the forbidden-app-settings list, the az-CLI zip deploy (Azure/functions-action is a single point of failure), instance sizing, and managed-identity storage auth. Use when adding a non-HTTP trigger, exceeding the 30s SWA limit, or fixing a Function App that landed on the wrong plan.
---

# Deploying FC1 Flex Consumption Function Apps

Use FC1 when SWA managed functions don't fit: timer triggers, queue triggers, AI workloads, or anything that runs longer than 30 seconds.

## Workflow checklist

Copy this checklist and tick items off:

```
FC1 Flex Consumption provisioning:
- [ ] Step 1: Confirm SP has User Access Administrator at the RG scope (needed for MI role assignments)
- [ ] Step 2: Deploy storage account with the deployment container (storage-for-fc1.bicep)
- [ ] Step 3: Deploy FC1 plan + Function App via Bicep (NEVER az CLI — it silently mis-creates the plan)
- [ ] Step 4: Verify properties.sku == "FlexConsumption" with az functionapp show
- [ ] Step 5: Confirm FUNCTIONS_WORKER_RUNTIME is NOT in app settings
- [ ] Step 6: Confirm package.json has "main": "dist/index.js" and "engines": { "node": "22" } (CommonJS — same as SWA)
- [ ] Step 7: Confirm src/index.ts imports every function file (a missing import = silent 404)
- [ ] Step 8: Deploy code with `az functionapp deployment source config-zip` (not Azure/functions-action); verify with `az functionapp show --query properties.sku` == FlexConsumption
- [ ] Step 9: Wait up to 10 min for MI role assignment propagation if first call fails
- [ ] Step 10: Restart the app once after the first deploy — the v4 Node host doesn't always discover functions from a fresh zip until it recycles
```

## Why this is hard

Azure Flex Consumption (FC1) looks similar to deprecated Linux Consumption (Y1) in the portal but behaves completely differently:

| | Linux Consumption (Y1) | Flex Consumption (FC1) |
|---|---|---|
| Status | **Retiring 2028-09-30**; no new language versions (Node 22 is the last) | Current, recommended; Node 24 GA; 512 MB instances GA |
| Deployment | `WEBSITE_RUN_FROM_PACKAGE` | **One Deploy** (blob-based) |
| `FUNCTIONS_WORKER_RUNTIME` | Required | **Forbidden** |
| CLI creation | Works | **Silently fails** to wrong plan |
| Storage auth | Connection string | `__accountName` (Managed Identity) |

## The CLI silently creates the wrong plan

**`az functionapp create --flexconsumption-location`** silently placed the app on `AustraliaEastLinuxDynamicPlan` (Y1/Dynamic) without error when this pack was built (CLI v2.83.0, 2026-03). Newer CLIs may behave; the failure is silent, so **always verify `properties.sku`** after any CLI creation, and prefer Bicep.

**`az appservice plan create --sku FC1`** returns no error but the plan is "Not Found" when queried.

**Always use ARM REST API or Bicep.** See [references/arm-rest-walkthrough.md](references/arm-rest-walkthrough.md) for the REST approach and [templates/flexConsumption.bicep](templates/flexConsumption.bicep) for the Bicep approach.

## App settings — forbidden values

```
DO set:
  AzureWebJobsStorage__accountName = <storage>    (DOUBLE underscore, MI auth)
  SQL_CONNECTION_STRING = <value>
  AI_PROJECT_ENDPOINT = <value>

DO NOT set:
  FUNCTIONS_WORKER_RUNTIME         — FORBIDDEN, causes "malformed content"
  WEBSITE_RUN_FROM_PACKAGE         — Y1 only
  WEBSITE_ENABLE_SYNC_UPDATE_SITE  — Y1 only
```

Runtime is declared in `functionAppConfig.runtime` on the resource, not in app settings. See [references/forbidden-settings.md](references/forbidden-settings.md).

## Code structure (CommonJS — same as SWA managed functions)

```json
// package.json
{ "main": "dist/index.js", "engines": { "node": "22" } }
```

```typescript
// src/index.ts — every function file imported for its side-effect registration
import './functions/myFunction';
```

```json
// tsconfig.json
{ "compilerOptions": { "module": "commonjs", "target": "ES2022" } }
```

**CommonJS is the proven shape** (`bc-videohub-lite`'s FC1 API). An earlier version of this skill mandated ESM (`"type": "module"` + `.js` import suffixes) for FC1 — no shipping project uses that, and Azure Functions' ESM support is still `.mjs`-only preview. The api/ folder you wrote for SWA moves to FC1 unchanged.

## Instance size and always-ready

`instanceMemoryMB` on `functionAppConfig.scaleAndConcurrency`: **512** (0.25 vCPU, cheapest, GA), **2048** (1 vCPU, the safe default for Node + mssql), **4096** (2 vCPU). Keep `alwaysReady: []` — always-ready instances bill continuously whether or not they run anything (cost-guardrails Guardrail #9). Accept the ~1s Flex cold start; it is far better than the ~2s floor of SWA managed functions.

## Deploying the code — az CLI, not the marketplace action

`Azure/functions-action` was disabled on GitHub from 2026-06-05 to 2026-06-10 and every pipeline that used it went red. The pack now deploys with plain CLI, which has no third-party dependency:

```yaml
- name: Build API
  working-directory: api
  run: |
    npm ci
    npm run build
    npm prune --omit=dev          # smaller zip; devDeps aren't needed at runtime

- name: Deploy API (Flex Consumption, One Deploy)
  run: |
    (cd api && zip -qr ../api-deploy.zip dist node_modules host.json package.json)
    az functionapp deployment source config-zip \
      --name "$FUNC_APP_NAME" --resource-group "$RG" --src api-deploy.zip
    # v4 Node host may not discover functions from a fresh zip until it recycles:
    az functionapp restart --name "$FUNC_APP_NAME" --resource-group "$RG"
```

Do **not** put `az functionapp restart` (or any config write) *immediately before* the zip deploy — Kudu aborts with "Do not perform a management operation and a deployment operation in quick succession". Config first, `sleep 30`, then deploy, then restart. If `config-zip` still reports "SCM container restart", retry once.

Proven: `bc-videohub-lite` (`deploy-production.yml`, commit 093639c), `trg-directory-website`.

## Required RBAC

| Role | Scope | Purpose |
|------|-------|---------|
| Storage Blob Data Owner | Function App's storage account | Host lease + deployment blob |
| Storage Blob Data Contributor | User blob storage | Read/write user blobs |

The deploying SP needs `User Access Administrator` to create these role assignments in Bicep. See [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md).

RBAC propagation can take up to 10 minutes after deploy. If the app fails to start immediately, wait and retry before debugging.

**Managed identity is now the standard for the app's data-plane auth too**, not just host storage — the same system-assigned identity authenticates to Azure SQL (Entra token) and signs user-delegation SAS for Blob Storage, so the stored SQL password and account key drop out of the runtime auth path (kept only as rollback). See [securing-azure-sql-and-storage-with-managed-identity](../securing-azure-sql-and-storage-with-managed-identity/SKILL.md); provision it from day one on new apps.

## Bicep resets app settings — restore them in a job that always runs

A Bicep deploy of the Function App **resets its app settings** to whatever the template declares. If your workflow sets extra settings by hand (auth-mode flags, API keys) in a later step and that step is skipped because a quality gate failed *after* infra ran, the app comes up with placeholders and 503s ("Service not configured"). This took a production API down on 2026-06-05.

Fix: put the settings-restore in its own job with `if: ${{ always() && needs.deploy-infra.result == 'success' }}`, decoupled from every test/lint gate, and pass the currently-live container/app image into Bicep so infra deploys never reset code either. See [securing-azure-sql-and-storage-with-managed-identity](../securing-azure-sql-and-storage-with-managed-identity/SKILL.md) "Durability".

## Can't change hosting plan on an existing app

If an app was accidentally created on Y1, you **must delete and recreate it**. The hosting plan cannot be migrated. If the name is soft-deleted (~24h), use a new name.

## Verification

```bash
az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" \
  --query "{sku:properties.sku, serverFarm:properties.serverFarmId}" -o json
# properties.sku MUST be "FlexConsumption"
# serverFarmId must NOT end with "LinuxDynamicPlan"
```

If `properties.sku` reads `Dynamic` or the plan id ends in `LinuxDynamicPlan` — wrong plan. Delete and recreate (soft-deleted names are held ~24h; pick a new name if blocked).

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — for the modular toggle to add FC1 to a project
- [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md) — User Access Administrator grant for MI role assignments
- [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) — for FC1-specific failure modes

## Checklist

- [ ] FC1 plan created via ARM REST API or Bicep (not CLI)
- [ ] Function app created via ARM with explicit `serverFarmId`
- [ ] `properties.sku = "FlexConsumption"` confirmed
- [ ] `FUNCTIONS_WORKER_RUNTIME` is NOT in app settings
- [ ] `AzureWebJobsStorage__accountName` used (double underscore)
- [ ] Managed identity has Storage Blob Data Owner
- [ ] SP has User Access Administrator at RG scope
- [ ] `package.json` has `"main": "dist/index.js"` and `"engines": { "node": "22" }` (CommonJS)
- [ ] `src/index.ts` imports all function files
- [ ] Deploy step is `az functionapp deployment source config-zip` + restart (no `Azure/functions-action`)
- [ ] App-settings restore runs in an `always()` job after infra
