# FC1 via ARM REST API — step by step

The `az` CLI silently mis-creates FC1 plans and apps. The Bicep approach (see [`templates/flexConsumption.bicep`](../templates/flexConsumption.bicep)) is preferred. If you must use the CLI, do so via `az rest`.

## Create FC1 App Service Plan

```bash
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/serverfarms/${FC_PLAN_NAME}?api-version=2023-12-01" \
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
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}?api-version=2023-12-01" \
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
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}/config/web?api-version=2023-12-01" \
  --body '{ "properties": { "cors": { "allowedOrigins": ["https://your-app.azurestaticapps.net", "http://localhost:5173"] } } }'
```

## GitHub Actions deployment step

```yaml
- uses: Azure/functions-action@v1.5.2   # Minimum version that detects FC1
  with:
    app-name: ${{ env.AZURE_FUNCTIONAPP_NAME }}
    package: functions-deploy.zip
```

Build pattern:

```yaml
- run: npm ci                    # all deps (typescript needed for build)
- run: npm run build             # compile → dist/
- run: npm ci --omit=dev         # prune devDeps for smaller zip
- run: zip -r ../deploy.zip dist/ node_modules/ host.json package.json
```
