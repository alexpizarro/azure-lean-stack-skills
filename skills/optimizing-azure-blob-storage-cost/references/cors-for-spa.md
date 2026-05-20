# CORS for SPA uploads and Range reads

Two browser scenarios need CORS on the blob service:

1. **Direct SAS uploads** — browser PUTs a file to a presigned URL
2. **Range reads** — video/audio players, `<img crossOrigin="anonymous">`, anything that needs `Range:` requests

## CORS rule template

```bicep
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            'https://app.example.com'              // prod
            'https://test.app.example.com'         // test
            'http://localhost:5173'                // local dev
          ]
          allowedMethods: ['GET', 'PUT', 'OPTIONS']
          allowedHeaders: ['*']                    // browser sends x-ms-* on uploads
          exposedHeaders: ['*']                    // needed so Range responses include Content-Range etc.
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}
```

## `allowedOrigins`

- **No wildcards in production.** `'*'` is convenient but exposes your storage to any origin.
- **Include `http://localhost:5173`** (or whatever your dev port is) for local development against real Azure storage.
- **Multiple environments** — include test + prod hostnames in one rule, or two rules with different origins.

## `allowedMethods`

- `GET` — reads (including Range)
- `PUT` — SAS uploads
- `OPTIONS` — preflight (browser auto-sends)
- `POST` — only if you're using append blobs or block-list operations from the browser
- `DELETE` — usually not needed from browser; do it server-side

## `allowedHeaders` and `exposedHeaders`

`*` is fine here because the actual security boundary is the SAS token / public-access flag, not the headers. CORS prevents an attacker on `evil.com` from issuing a request *as your user*; SAS prevents them from issuing one at all.

`exposedHeaders: ['*']` is required for the video player to see `Content-Range`, `Content-Length`, custom `x-ms-*` headers.

## SAS upload — the JavaScript side

```typescript
async function uploadViaSas(file: File, sasUrl: string) {
  const res = await fetch(sasUrl, {
    method: 'PUT',
    headers: {
      'x-ms-blob-type': 'BlockBlob',
      'Content-Type': file.type,
    },
    body: file,
  });
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
}
```

Generate the SAS URL server-side; never embed the storage key in the SPA.

## Range request — video player

```html
<video crossOrigin="anonymous" src="https://store.blob.core.windows.net/videos/abc.mp4" controls></video>
```

Without `exposedHeaders: ['*']` (or at minimum `Content-Range`), the player can't seek.

## Per-container CORS doesn't exist

CORS is configured at the **blob service** level, not per container. All containers in the account share the same CORS rules. Plan accordingly.

## Multi-environment workaround

If you need different CORS for test vs prod, deploy separate storage accounts (one per env). The naming convention already does this: `{org}{project}storetest` vs `{org}{project}storeprod`.

## Verifying

```bash
# Show current CORS
az storage cors list --account-name "$SA" --services b

# Test from a browser
curl -i -X OPTIONS "https://${SA}.blob.core.windows.net/?comp=list" \
  -H "Origin: https://app.example.com" \
  -H "Access-Control-Request-Method: GET"
# Expect: Access-Control-Allow-Origin: https://app.example.com
```
