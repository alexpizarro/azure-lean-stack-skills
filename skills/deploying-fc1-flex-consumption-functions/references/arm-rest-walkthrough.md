# FC1 via ARM REST API — step by step

The `az` CLI silently mis-creates FC1 plans and apps. The Bicep approach (see [`templates/flexConsumption.bicep`](../templates/flexConsumption.bicep)) is preferred. If you must use the CLI, do so via `az rest`.

## Create FC1 App Service Plan

```bash
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/serverfarms/${FC_PLAN_NAME}?api-version=2024-04-01" \
  --body "{
    \"location\": \"${LOCATION}\",
    \"kind\": \"functionapp\",
    \"sku\": { \"name\": \"FC1\", \"tier\": \"FlexConsumption\" },
    \"properties\": { \"reserved\": true }
  }"
```

## Create Function App on FC1 plan

```bash
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}?api-version=2024-04-01" \
  --body "{
    \"location\": \"${LOCATION}\",
    \"kind\": \"functionapp,linux\",
    \"identity\": { \"type\": \"SystemAssigned\" },
    \"properties\": {
      \"serverFarmId\": \"/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/serverfarms/${FC_PLAN_NAME}\",
      \"functionAppConfig\": {
        \"deployment\": {
          \"storage\": {
            \"type\": \"blobContainer\",
            \"value\": \"https://${STORAGE_ACCOUNT}.blob.core.windows.net/app-package-${FUNCTION_APP_NAME}\",
            \"authentication\": { \"type\": \"SystemAssignedIdentity\" }
          }
        },
        \"runtime\": { \"name\": \"node\", \"version\": \"22\" }
      }
    }
  }"
```

## Set CORS

`az functionapp cors add` returns `Bad Request` on FC1. Use ARM REST:

```bash
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}/config/web?api-version=2024-04-01" \
  --body '{ "properties": { "cors": { "allowedOrigins": ["https://your-app.azurestaticapps.net", "http://localhost:5173"] } } }'
```

## GitHub Actions deployment step

Use the CLI, not `Azure/functions-action` (that repo was disabled on GitHub for five days in June 2026 and broke every pipeline that depended on it):

```yaml
- run: npm ci                    # all deps (typescript needed for build)
  working-directory: api
- run: npm run build             # compile → dist/
  working-directory: api
- run: npm prune --omit=dev      # drop devDeps for a smaller zip
  working-directory: api
- run: |
    (cd api && zip -qr ../deploy.zip dist node_modules host.json package.json)
    az functionapp deployment source config-zip \
      --name "$FUNC_APP_NAME" --resource-group "$RG" --src deploy.zip
    az functionapp restart --name "$FUNC_APP_NAME" --resource-group "$RG"
```

The SP needs Contributor on the Function App and `Storage Blob Data Contributor` on the deployment storage account (the zip lands in `app-package-{name}` via One Deploy).
