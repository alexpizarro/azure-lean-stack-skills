# Naming formula

`{org}-{project}-{component}-{env}` — applied to every Azure resource.

| Token | Description | Example |
|-------|-------------|---------|
| `{org}` | Short org/company prefix | `acme` |
| `{project}` | Short app name | `taskapp` |
| `{component}` | Resource type | `rg`, `swa`, `sql`, `sqldb`, `store`, `aca`, `ai`, `logs` |
| `{env}` | Environment | `test`, `prod` |

## Single source of truth

`org` and `project` are set ONCE in `infra/environments/{env}.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": { "value": "test" },
    "org":             { "value": "acme" },
    "project":         { "value": "taskapp" }
  }
}
```

Every resource name in `main.bicep` is derived from these two values + `environmentName`:

```bicep
var baseName = '${org}-${project}'
var rgName   = '${baseName}-rg-${environmentName}'
var swaName  = '${baseName}-swa-${environmentName}'
var sqlName  = '${baseName}-sql-${environmentName}'
```

## Storage account name exception

Storage accounts disallow hyphens and cap at 24 characters. Use the no-hyphen form:

```bicep
var storageAccountName = '${org}${project}store${environmentName}'   // e.g. acmetaskappstoretest
```

If the resulting name exceeds 24 chars, shorten `project` or drop the `store` suffix.

## Example: org=acme, project=taskapp

| Resource | Test | Prod |
|----------|------|------|
| Resource Group | `acme-taskapp-rg-test` | `acme-taskapp-rg-prod` |
| Static Web App | `acme-taskapp-swa-test` | `acme-taskapp-swa-prod` |
| SQL Server | `acme-taskapp-sql-test` | `acme-taskapp-sql-prod` |
| SQL Database | `acme-taskapp-sqldb-test` | `acme-taskapp-sqldb-prod` |
| Storage account | `acmetaskappstoretest` | `acmetaskappstoreprod` |
| App Insights | `acme-taskapp-ai-test` | `acme-taskapp-ai-prod` |
| Log Analytics | `acme-taskapp-logs-test` | `acme-taskapp-logs-prod` |
| Container App | `acme-taskapp-aca-test` | `acme-taskapp-aca-prod` |
| GitHub SP | `acme-taskapp-github-test` | `acme-taskapp-github-prod` |

## Tags

Every resource gets the same tag block. Set in `main.bicep` and pass to every module:

```bicep
var tags = {
  environment: environmentName
  project: project
  organization: org
  managedBy: 'bicep'
}
```
