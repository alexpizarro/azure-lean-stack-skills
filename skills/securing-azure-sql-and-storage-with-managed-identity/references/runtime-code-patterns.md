# Runtime code patterns — flag-gated MI auth

Copy-adaptable Node.js / Azure Functions v4 code for the two auth switches. Both default to the
legacy path, so dropping this in is a **no-op until you set the flag**. `@azure/identity` provides the
`DefaultAzureCredential` that resolves the compute's system-assigned managed identity.

```
npm i @azure/identity @azure/storage-blob
```

Versions (2026-09): `@azure/identity ^4.13`, `@azure/storage-blob ^12.33`, `mssql ^12.7` — all require Node ≥ 22, which is the pack default.

---

## SQL — `SQL_AUTH_MODE` (default `connstr`)

`msi` builds an `mssql` config with **no password**. `azure-active-directory-default` delegates to
`@azure/identity`'s `DefaultAzureCredential`, which finds the Function App's MI automatically. Server
and database come from `SQL_SERVER` / `SQL_DATABASE`, or are parsed out of the existing connection
string so you don't have to duplicate config.

```ts
// db.ts
import sql from 'mssql';

const AUTH_MODE = process.env.SQL_AUTH_MODE ?? 'connstr';        // 'connstr' | 'msi'
const CONN_STR = process.env.SQL_CONNECTION_STRING ?? '';

function fromConnStr(re: RegExp): string {
  const m = CONN_STR.match(re);
  return m ? m[1].trim() : '';
}

export function buildSqlConfig(): sql.config | string {
  if (AUTH_MODE === 'msi') {
    // Entra token auth — NO password in config. DefaultAzureCredential picks up the MI.
    return {
      server: process.env.SQL_SERVER || fromConnStr(/Server=tcp:([^,;]+)/i),
      // The scaffold's connection string uses `Database=`; ADO-style strings use `Initial Catalog=`.
      database: process.env.SQL_DATABASE || fromConnStr(/(?:Initial Catalog|Database)=([^;]+)/i),
      authentication: { type: 'azure-active-directory-default' },
      options: { encrypt: true },
    };
  }
  // Legacy / rollback: mssql parses the ADO connection string (User Id + Password) directly.
  return CONN_STR;
}

// usage stays identical for both modes:
export const getPool = (() => {
  let pool: Promise<sql.ConnectionPool> | undefined;
  return () => (pool ??= sql.connect(buildSqlConfig() as sql.config));
})();
```

---

## Storage — `STORAGE_AUTH_MODE` (default `key`)

`msi` uses a `DefaultAzureCredential` `BlobServiceClient` and signs **user-delegation** SAS. The key
detail: **SAS signers are synchronous, but the user-delegation key is fetched async** — so it must be
primed and cached before any signing happens (see the warm-up hook below).

```ts
// blob.ts
import {
  BlobServiceClient, StorageSharedKeyCredential,
  generateBlobSASQueryParameters, BlobSASPermissions, SASProtocol,
  type UserDelegationKey,
} from '@azure/storage-blob';
import { DefaultAzureCredential } from '@azure/identity';

const AUTH_MODE = process.env.STORAGE_AUTH_MODE ?? 'key';        // 'key' | 'msi'
const CONN_STR = process.env.STORAGE_CONNECTION_STRING ?? '';    // key path + Azurite local-dev
// Account name/key come from the connection string on the key path (no extra settings);
// STORAGE_ACCOUNT_NAME is only needed on the msi path (no connection string there).
const connPart = (k: string) => CONN_STR.match(new RegExp(`${k}=([^;]+)`, 'i'))?.[1] ?? '';
const ACCOUNT = process.env.STORAGE_ACCOUNT_NAME || connPart('AccountName');
const ACCOUNT_KEY = connPart('AccountKey');

let msiClient: BlobServiceClient | undefined;
let keyClient: BlobServiceClient | undefined;
let cachedKey: { key: UserDelegationKey; expiresOn: Date } | undefined;

function serviceClient(): BlobServiceClient {
  if (AUTH_MODE === 'msi') {
    return (msiClient ??= new BlobServiceClient(
      `https://${ACCOUNT}.blob.core.windows.net`, new DefaultAzureCredential()));
  }
  // key path — also the Azurite / local-dev path (connection string endpoint-aware)
  return (keyClient ??= BlobServiceClient.fromConnectionString(CONN_STR));
}

// CRITICAL: async — must be primed BEFORE any (synchronous) SAS sign. See the preInvocation hook.
export async function ensureUserDelegationKey(): Promise<void> {
  if (AUTH_MODE !== 'msi') return;                               // no-op on key / local path
  const now = Date.now();
  if (cachedKey && cachedKey.expiresOn.getTime() - now > 60_000) return;   // refresh within ~60s of expiry
  const startsOn = new Date(now - 5 * 60_000);                  // 5-min clock-skew grace
  const expiresOn = new Date(now + 60 * 60_000);                // 1h key lifetime
  const key = await serviceClient().getUserDelegationKey(startsOn, expiresOn);
  cachedKey = { key, expiresOn };
}

export function signReadSas(container: string, blob: string, ttlMinutes = 15): string {
  const now = Date.now();
  const expiresOn = new Date(now + ttlMinutes * 60_000);
  const values = {
    containerName: container, blobName: blob,
    permissions: BlobSASPermissions.parse('r'),
    startsOn: new Date(now - 5 * 60_000), expiresOn,
    protocol: SASProtocol.Https,
  };
  // Endpoint-aware: Azure is https://{account}.blob.core.windows.net, Azurite is
  // http://127.0.0.1:10000/devstoreaccount1. Take it from the client, never a literal.
  const blobUrl = serviceClient().getContainerClient(container).getBlobClient(blob).url;
  if (AUTH_MODE === 'msi') {
    if (!cachedKey) throw new Error('user delegation key not primed — call ensureUserDelegationKey() first');
    // 3-ARG form for user-delegation SAS: (values, delegationKey, accountName)
    const sas = generateBlobSASQueryParameters(values, cachedKey.key, ACCOUNT).toString();
    return `${blobUrl}?${sas}`;
  }
  // key path — 2-arg form with the shared-key credential parsed from the connection string.
  const cred = new StorageSharedKeyCredential(ACCOUNT, ACCOUNT_KEY);
  const sas = generateBlobSASQueryParameters(values, cred).toString();
  return `${blobUrl}?${sas}`;
}
```

> The key path derives account name + key from `STORAGE_CONNECTION_STRING` (the setting the scaffold
> already has), so no extra `STORAGE_ACCOUNT_KEY` setting is needed. The `msi` branch never touches a key.

---

## The warm-up hook (Azure Functions v4) — MANDATORY for the storage `msi` path

A global `preInvocation` hook primes the delegation key before **every** invocation. It is a no-op
unless `STORAGE_AUTH_MODE=msi`, instant once cached, and self-refreshing. **Without it, the first cold
SAS-sign throws "not primed".** Register it in the entrypoint that imports your functions.

```ts
// index.ts
import { app } from '@azure/functions';
import { ensureUserDelegationKey } from './lib/blob';

app.hook.preInvocation(async () => {
  await ensureUserDelegationKey();   // no-op unless msi; instant when cached
});

// ... then import all function files (CommonJS — the proven shape on FC1 and SWA alike)
import './functions/myFunction';
```

---

## Local dev

Azurite has no Entra / user-delegation support, so **local-dev stays on the key path**. Leave
`STORAGE_AUTH_MODE` and `SQL_AUTH_MODE` unset locally (they default to `key` / `connstr`) and point
the connection strings at Azurite + local SQL as usual. The `msi` branches only ever run in Azure,
where `DefaultAzureCredential` resolves the deployed identity.
