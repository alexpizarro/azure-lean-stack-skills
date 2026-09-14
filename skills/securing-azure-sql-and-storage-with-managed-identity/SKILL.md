---
name: securing-azure-sql-and-storage-with-managed-identity
description: Moves an Azure Functions app's RUNTIME data-plane auth off the stored SQL password and storage account key onto the compute's system-assigned managed identity — Entra token auth for Azure SQL and user-delegation SAS for Blob Storage. Ships flag-gated (default OFF, old paths byte-identical) so cutover is a no-op until flipped and rollback is one setting. Covers the Entra-admin + MI-DB-user + storage-RBAC one-time setup, the async user-delegation-key priming that SAS signing requires, and the bicep-resets-app-settings durability trap. Use when hardening a deployment off secrets, when a security review flags a stored SQL password / account key, or as the DEFAULT auth for any new Function App + SQL + Blob deployment.
---

# Securing Azure SQL and Storage with Managed Identity

Kill the stored SQL password and the storage account key from the **runtime** auth path. Use the
compute's **system-assigned managed identity** (MI) instead: Entra token auth for Azure SQL,
user-delegation SAS for Blob Storage. Managed identity is **free**. Keep the connection string and
account key present as **instant rollback only** — never the primary auth.

This is the DEFAULT for new deployments. Username/password + account key is legacy / rollback.

> **Scope note.** This is about the app's *data-plane* auth to SQL and to *user* blobs. It is
> separate from FC1's *host* storage MI (`AzureWebJobsStorage__accountName`, the deployment + host
> lease), which [deploying-fc1-flex-consumption-functions](../deploying-fc1-flex-consumption-functions/SKILL.md)
> already covers. Both use the same system-assigned identity; they authorise different things.
>
> **Applies to FC1 / Container Apps / App Service — not SWA managed functions.** SWA managed
> functions have no managed identity and no Key Vault references; if the API lives there, move it
> to FC1 first (the code is the same CommonJS shape).

Proven end-to-end on Azure Functions (Flex Consumption) + Azure SQL + Blob Storage, 2026-07-17.

## Workflow checklist

Copy this checklist and tick items off. **SQL and storage are independent — do SQL fully first.**

```
Managed-identity data-plane auth:
- [ ] Step 1: Add @azure/identity to the api package; ship the flag-gated code (both flags default OFF)
- [ ] Step 2: SQL server Entra admin set (additive — sqladmin still works)
- [ ] Step 3: MI DB user created FROM EXTERNAL PROVIDER + db_datareader/db_datawriter (connected AS the Entra admin; db_ddladmin only if the app runs DDL)
- [ ] Step 4: Storage RBAC — MI granted Storage Blob Data Contributor at ACCOUNT scope (add Storage Blob Delegator only if the data role is scoped narrower)
- [ ] Step 5: preInvocation user-delegation-key warm-up deployed (needed before any storage cutover)
- [ ] Step 6: Add SQL_AUTH_MODE + STORAGE_AUTH_MODE to the deploy's configure-function-app --settings list
- [ ] Step 7: Cut SQL over — SQL_AUTH_MODE=msi, restart, validate a SQL-backed read
- [ ] Step 8: Cut storage over — STORAGE_AUTH_MODE=msi, restart, validate a SAS BYTE fetch (200 + bytes)
- [ ] Step 9: Rollback rehearsed — unset a flag → back to password/key (both still present)
```

## The model

| Concern | Legacy (rollback) | Managed identity (default) |
|---|---|---|
| SQL auth | `User Id=...;Password=...` in the connection string | Entra token via `DefaultAzureCredential` — no password in config |
| Blob auth | account key → `StorageSharedKeyCredential` SAS | `DefaultAzureCredential` BlobServiceClient → **user-delegation SAS** |
| Secret at rest | password + account key in app settings | none in the auth path (both kept only as rollback) |
| Cost | — | **$0** (MI is free) |

The flags let the old paths stay **byte-identical** until you flip them, so shipping the code is safe
and the cutover is reversible per-resource.

## The code — flag-gated, default OFF

Two env flags select the auth path. Default = the legacy path, so the change is a no-op until set.
Full copy-adaptable code (SQL config, storage user-delegation SAS, and the warm-up hook) is in
[references/runtime-code-patterns.md](references/runtime-code-patterns.md). Summary:

- **SQL** — env `SQL_AUTH_MODE` (default `connstr`). `msi` ⇒ an `mssql` config with **no password** and
  `authentication: { type: 'azure-active-directory-default' }` (the `@azure/identity`
  `DefaultAzureCredential` picks up the MI). `server`/`database` come from `SQL_SERVER` / `SQL_DATABASE`
  or are parsed out of the existing connection string.
- **Storage** — env `STORAGE_AUTH_MODE` (default `key`). `msi` ⇒ a `DefaultAzureCredential`
  `BlobServiceClient` plus **user-delegation SAS**: `getUserDelegationKey(...)` then the **3-arg**
  `generateBlobSASQueryParameters(values, delegationKey, accountName)`. Azurite / local-dev stays on
  the key path.
- **The async-vs-sync trap (CRITICAL).** SAS signers are **synchronous**, but the user-delegation key
  is fetched **async**. Cache it and prime it via `ensureUserDelegationKey()` from a global
  `app.hook.preInvocation` (Azure Functions v4) that runs **before every invocation** — a no-op unless
  `msi`, instant when cached, refreshing within ~60s of expiry. **Without this warm-up the first cold
  SAS-sign throws "not primed".** Deploy the warm-up *before* you flip `STORAGE_AUTH_MODE=msi`.
- Add **`@azure/identity`** to the api package.

## Azure one-time setup (per environment / per DB)

Do this once per environment before flipping the flags. All three steps are idempotent and additive.

### 1. SQL server Entra admin (additive — does not disturb sqladmin)

```bash
az sql server ad-admin create -g <rg> -s <sqlserver> \
  --display-name "<upn-or-group>" --object-id "<entra-object-id>"
```

Setting the Entra admin is **additive**: `sqladmin` still authenticates, so the deploy-time migration
runner (which uses sqladmin) is undisturbed. **Keep the connection string.**

### 2. Create the MI DB user (connected AS THE ENTRA ADMIN)

A SQL login **cannot** create an external-provider user — you must be connected as an **Entra**
principal that is the server's Entra admin. The MI's Entra display name **==** the Function App name.

```sql
CREATE USER [<func-app-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<func-app-name>];
ALTER ROLE db_datawriter ADD MEMBER [<func-app-name>];
-- db_ddladmin ONLY if the app itself runs DDL at runtime. Migrations run as sqladmin, so the default is no.
```

Use the idempotent [templates/setup-mi-db-user.sql](templates/setup-mi-db-user.sql) (each grant
guarded with `IS_ROLEMEMBER(...) = 0`; `@grantDdl` defaults to 0). Two ways to run it as an Entra principal:

- **Human, interactively** (one copy-paste, `-G` = Entra auth):
  ```bash
  sqlcmd -G -S <sqlserver>.database.windows.net -d <database> \
    -Q "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='<func-app-name>') CREATE USER [<func-app-name>] FROM EXTERNAL PROVIDER; IF IS_ROLEMEMBER('db_datareader','<func-app-name>')=0 ALTER ROLE db_datareader ADD MEMBER [<func-app-name>]; IF IS_ROLEMEMBER('db_datawriter','<func-app-name>')=0 ALTER ROLE db_datawriter ADD MEMBER [<func-app-name>];"
  ```
- **Agent, no interactive OAuth** — works IF the human has already `az login`'d and is the SQL Entra
  admin. Mint a token for the SQL resource and connect with `mssql` access-token auth. See
  [scripts/create-mi-db-user.cjs](scripts/create-mi-db-user.cjs):
  ```js
  const token = JSON.parse(execSync(
    'az account get-access-token --resource https://database.windows.net/ -o json').toString()
  ).accessToken;
  await sql.connect({ server, database,
    authentication: { type: 'azure-active-directory-access-token', options: { token } },
    options: { encrypt: true } });
  ```

SQL firewall blocks non-Azure IPs, so add a temp rule for your IP to run the `CREATE USER`, then
delete it (the Function App connects over the Azure backbone — no IP rule needed at runtime):

```bash
MYIP=$(curl -s https://api.ipify.org)
az sql server firewall-rule create -g <rg> -s <sqlserver> -n tmp-mi-setup \
  --start-ip-address "$MYIP" --end-ip-address "$MYIP"
# ... run the CREATE USER above ...
az sql server firewall-rule delete -g <rg> -s <sqlserver> -n tmp-mi-setup
```

### 3. Storage RBAC (data plane)

Grant the MI **Storage Blob Data Contributor at the storage-account scope**. That built-in role
already includes `Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action`
(verified against the live role definition), so it can mint user-delegation SAS on its own.
**Storage Blob Delegator** is only needed when the data role is scoped *below* the account
(a single container), because `getUserDelegationKey` is an account-level call. The proven
project granted both; the second is harmless.

```bash
MI_OID=$(az functionapp identity show -g <rg> -n <func-app-name> --query principalId -o tsv)
SCOPE="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<account>"

az role assignment create --assignee-object-id "$MI_OID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SCOPE"     # data plane read/write + user-delegation key
# Only if you scope the data role to a container instead of the account:
# az role assignment create --assignee-object-id "$MI_OID" --assignee-principal-type ServicePrincipal \
#   --role "Storage Blob Delegator" --scope "$SCOPE"
```

Assigning roles needs **Owner** or **User Access Administrator** — a Contributor-only deploy SP
cannot do it, so run these in an owner `az` session or out-of-band. RBAC propagation can take a few
minutes.

## Runtime cutover + validate

Cut over one resource at a time, validating each before the next. Both are reversible.

```bash
# SQL first (independent of storage)
az functionapp config appsettings set -g <rg> -n <func-app-name> --settings SQL_AUTH_MODE=msi
az functionapp restart -g <rg> -n <func-app-name>
# validate: hit an endpoint that does a SQL-backed READ → expect 200 with data

# Then storage (only after the preInvocation warm-up is deployed)
az functionapp config appsettings set -g <rg> -n <func-app-name> --settings STORAGE_AUTH_MODE=msi
az functionapp restart -g <rg> -n <func-app-name>
# validate: fetch a SAS URL and pull BYTES → expect 200 + non-empty body (not just a signed URL)
```

Validate the storage cutover with an actual **byte fetch**, not just a 200 on the API that *mints*
the SAS — a broken delegation key still returns a URL; only the byte fetch proves the signature.

**Rollback** = unset the flag (`az functionapp config appsettings delete --setting-names SQL_AUTH_MODE`
or `STORAGE_AUTH_MODE`) → back to password/key, both still present. Restart.

## Durability — the biggest gotcha

The bicep infra deploy **RESETS** the Function App's app-settings, and the `configure-function-app`
restore step only re-sets its **known** list. A `SQL_AUTH_MODE` / `STORAGE_AUTH_MODE` you set by hand
is **NOT** in that list, so the next deploy **silently wipes it** — the app reverts to password/key
with no error.

**Fix:** add both flags to the `configure-function-app` `--settings` list, **per-environment** (only
for envs whose MI DB user + storage RBAC actually exist — a flag without the grant fails closed).
Keep `SQL_CONNECTION_STRING` / `STORAGE_CONNECTION_STRING` in the list as rollback.

```bash
# in the deploy's configure-function-app step, for MI-enabled envs only
az functionapp config appsettings set -g <rg> -n <func-app-name> --settings \
  SQL_AUTH_MODE=msi \
  STORAGE_AUTH_MODE=msi \
  SQL_CONNECTION_STRING="$SQL_CONNECTION_STRING" \
  STORAGE_CONNECTION_STRING="$STORAGE_CONNECTION_STRING"
```

## Beyond SQL and Blob — the same identity, narrower roles

The pattern generalises to any Azure API the app calls: give the system-assigned MI the **narrowest role at the narrowest scope**, and expect the built-in roles to be too broad.

| Need | Role | Why not the obvious one |
|---|---|---|
| Start a Container Apps Job from the API | Custom role: `Microsoft.App/jobs/read` + `jobs/start/action` (+ `jobs/executions/read`), scoped to the **job** | "Container Apps Contributor" has **no** `jobs/*` actions and grants write/delete on every app in the RG |
| Pull a private image from ACR | `AcrPull` on the **registry resource** | `AcrPush` alone lacks `registries/read`, so `az acr build` fails with "could not be found" |
| Call Azure OpenAI keylessly | `Cognitive Services OpenAI User` on the account, with `disableLocalAuth: true` and a `customSubDomainName` (required for Entra token auth) | Keys are a rotation liability; the sub-domain is easy to forget |

Custom role definitions and assignments both need `Microsoft.Authorization/roleAssignments/write` (Owner or User Access Administrator). The CI SPs are Contributor-only by design, so **every RBAC module is flag-gated default-OFF and applied out-of-band once** (`enableStorageMsiRbac`-style params in `main.bicep`). Allow 3–4 minutes for propagation on first use and retry before concluding failure.

## Operational gotchas (all hit for real)

| Gotcha | Fix |
|---|---|
| **403 on `getUserDelegationKey` although the MI has Blob Data Contributor.** The data role was scoped to a *container*; the delegation key is an *account*-level call. | Scope Blob Data Contributor at the storage account, or add Storage Blob Delegator at the account. |
| **setup.sql placeholder guard self-defeats.** A naive global find/replace of the `REPLACE_WITH_FUNCTION_APP_NAME` token rewrites BOTH the `DECLARE` value AND the guard's literal → the guard compares the real name to itself and always throws. | Split the guard literal — `N'REPLACE_' + N'WITH_FUNCTION_APP_NAME'` — so a full-token replace can't touch it. See the template. Or use the inline `sqlcmd` one-liner (no placeholder at all). |
| **`require('mssql')` resolves from the SCRIPT's dir, not cwd.** A helper script `require`-ing mssql looks in *its own* `node_modules`, not the shell's cwd. | Run helpers from the app's `api/` dir, or use an absolute `require` path to the api's `node_modules/mssql`. |
| **Single-quotes in `node -e '...'` collide with SQL string literals.** The inline `-e` script's quotes fight the SQL `'literals'`. | Write the helper to a `.cjs` **file** (as in `scripts/create-mi-db-user.cjs`) — no quote collision. |
| **SQL firewall blocks your IP** for the `CREATE USER`. | Add a temp firewall rule for your IP, run it, delete the rule. The Function App uses the Azure backbone at runtime (no IP rule). |
| **First cold SAS-sign throws "not primed".** | Deploy the `preInvocation` `ensureUserDelegationKey()` warm-up BEFORE flipping `STORAGE_AUTH_MODE=msi`. |
| **`mssql` v12 no longer clones config objects.** A config you mutate after `sql.connect()` (e.g. swapping `authentication`) is undefined behaviour. | Build a fresh config object per mode; never edit one that's been passed to the pool. |
| **Infra deploy wipes the flags** (see Durability). | Flags live in the `configure-function-app` job that runs `if: always() && needs.deploy-infra.result == 'success'`, decoupled from every quality gate — a gate failing *after* infra ran once took prod down with 503 "Service not configured". |

## New deployments = MI by default

For any new tenant / app, provision MI from the start — do not stand up a password-only app and
retrofit:

1. Provision the **Entra admin**, the **MI DB user**, and the **storage RBAC** (both roles) as part
   of provisioning.
2. Ship the **flag-gated code** (both flags default OFF; `@azure/identity` in the api package; the
   `preInvocation` warm-up wired in).
3. Set **`SQL_AUTH_MODE=msi` and `STORAGE_AUTH_MODE=msi` in the deploy's configure step from day one**,
   with `SQL_CONNECTION_STRING` / `STORAGE_CONNECTION_STRING` retained as rollback.

Username/password + account key is legacy / rollback-only.

## Composes with

- [deploying-fc1-flex-consumption-functions](../deploying-fc1-flex-consumption-functions/SKILL.md) — MI for the app's *host* storage; this skill adds MI for its *data-plane* auth
- [configuring-azure-oidc-for-github-actions](../configuring-azure-oidc-for-github-actions/SKILL.md) — the deploy SP needs Owner / User Access Administrator to assign the storage roles
- [managing-azure-sql-migrations](../managing-azure-sql-migrations/SKILL.md) — the sqladmin migration runner stays on the connection string (Entra admin is additive)
- [applying-azure-cost-guardrails](../applying-azure-cost-guardrails/SKILL.md) — MI is free; removing the account-key path removes a rotation liability at no cost
- [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) — gotcha #49 (settings reset), #4 (roleAssignments 403), and the MI table in this skill for "not primed" / 403 on `getUserDelegationKey` (missing Delegator)
- [deploying-azure-container-apps](../deploying-azure-container-apps/SKILL.md) — the custom job-start role and shared-ACR pull identity

## Checklist

- [ ] `@azure/identity` added to the api package
- [ ] Code is flag-gated; both flags default OFF (legacy paths byte-identical)
- [ ] `preInvocation` `ensureUserDelegationKey()` warm-up wired in and deployed
- [ ] SQL server Entra admin set (sqladmin still works)
- [ ] MI DB user created FROM EXTERNAL PROVIDER + `db_datareader`/`db_datawriter` (`db_ddladmin` only if the app runs DDL)
- [ ] MI granted Storage Blob Data Contributor at account scope (Delegator only for container-scoped grants)
- [ ] `SQL_AUTH_MODE` + `STORAGE_AUTH_MODE` added to `configure-function-app --settings` (per MI-enabled env)
- [ ] Connection string + account key retained in the settings list as rollback
- [ ] SQL cutover validated by a SQL-backed read
- [ ] Storage cutover validated by a SAS **byte** fetch (200 + bytes)
- [ ] Rollback (unset flag → password/key) rehearsed
