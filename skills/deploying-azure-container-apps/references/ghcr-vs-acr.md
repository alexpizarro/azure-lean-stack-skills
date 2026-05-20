# Image registry — GHCR vs ACR vs Docker Hub

| Registry | Cost | Auth | When to use |
|----------|------|------|-------------|
| **GHCR** (`ghcr.io`) | Free for public; free up to 500MB for private (in personal); included in GitHub Team/Enterprise | GitHub token; or anonymous for public | Default for GitHub-hosted projects with non-secret images |
| **Azure Container Registry (ACR)** | Basic ~$5/mo, Standard ~$20/mo, Premium ~$50/mo | Managed Identity (best), admin user (avoid), service principal | Private images requiring fine-grained Azure RBAC, geo-replication (Premium), or content trust |
| **Docker Hub** | Free anonymous (rate-limited), Pro ~$5/mo for 5000 pulls/day | Username/token | Last resort — rate limits will burn you in production |

## Decision tree

```
Is the image secret/proprietary?
├─ NO  → GHCR public (free, no rate limits when pulled into Azure)
└─ YES → Will Azure resources pull it?
        ├─ YES → ACR (best Azure integration, MI pull)
        └─ NO  → GHCR private with a token (cheaper for low volume)
```

## Docker Hub rate limits

Anonymous pulls from Docker Hub are limited to **100 pulls per 6 hours per IP**. In Azure, multiple apps can share a NAT IP, so the limit hits fast. Symptoms:

```
toomanyrequests: You have reached your unauthenticated pull rate limit.
```

If you must use Docker Hub:
1. Pin tags (avoid `:latest`)
2. Use authenticated pulls — even a free Docker Hub account doubles the limit
3. Or mirror the image into ACR / GHCR

## GHCR setup for a private image

Container App needs a GitHub PAT with `read:packages` scope, stored as a secret:

```bash
az containerapp secret set --name "$APP_NAME" --resource-group "$RG" \
  --secrets "ghcr-pull=$GITHUB_PAT"
```

Then in Bicep:

```bicep
configuration: {
  registries: [
    {
      server: 'ghcr.io'
      username: 'set-by-github-actions'      // or the GitHub username
      passwordSecretRef: 'ghcr-pull'
    }
  ]
}
```

The username can be set with `az containerapp registry set --server ghcr.io --username ...`.

## ACR with Managed Identity (recommended for private ACR)

```bicep
// User-assigned MI on the app
identity: {
  type: 'UserAssigned'
  userAssignedIdentities: { '${miId}': {} }
}

// Grant AcrPull
resource raAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, mi.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  properties: {
    principalId: mi.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalType: 'ServicePrincipal'
  }
}

// On the container app
configuration: {
  registries: [
    { server: '${acrName}.azurecr.io', identity: mi.id }
  ]
}
```

No secrets to rotate; ACR pulls happen via the MI.

## Cost recap for small projects

- **GHCR public:** $0
- **Docker Hub anonymous (with pinning):** $0 but fragile
- **ACR Basic:** ~$5/mo flat
- **GitHub Container Registry private (personal):** $0 up to 500MB
- **Docker Hub Pro:** ~$5/mo

For most low-cost consumer projects, GHCR is the right answer.
