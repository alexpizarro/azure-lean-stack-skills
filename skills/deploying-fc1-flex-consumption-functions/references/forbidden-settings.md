# FC1 forbidden app settings

| Setting | Why forbidden | What to use instead |
|---------|---------------|--------------------|
| `FUNCTIONS_WORKER_RUNTIME` | Causes "malformed content" deployment failure on FC1 | Declare runtime in `functionAppConfig.runtime` on the site resource |
| `WEBSITE_RUN_FROM_PACKAGE` | Y1 deployment mechanism — FC1 uses One Deploy (blob-based) | Don't set; FC1 handles this automatically |
| `WEBSITE_ENABLE_SYNC_UPDATE_SITE` | Y1-only | Don't set |
| `AzureWebJobsStorage` (single underscore) | Single-underscore = connection-string auth; FC1 prefers MI | `AzureWebJobsStorage__accountName` (double underscore, MI auth) |

## Required app settings on FC1

```
AzureWebJobsStorage__accountName = <storage-account-name>
```

That's the only mandatory one. Everything else (SQL conn string, API endpoints, etc.) is per-project.

## Runtime declared on the resource, not in app settings

Bicep:

```bicep
properties: {
  functionAppConfig: {
    runtime: {
      name: 'node'
      version: '22'
    }
  }
}
```

ARM REST: same, in the body of the PUT to `Microsoft.Web/sites`.

## Verifying

```bash
az functionapp config appsettings list \
  --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" \
  --query "[].name" -o tsv | grep -E "FUNCTIONS_WORKER_RUNTIME|WEBSITE_RUN_FROM_PACKAGE"
# Should return nothing.
```
