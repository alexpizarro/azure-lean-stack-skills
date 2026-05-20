# Federated credentials reference

## Subject format

For a GitHub Actions workflow triggered by a branch push:

```
repo:{GitHubOrg}/{Repo}:ref:refs/heads/{branch}
```

For a PR-triggered workflow:

```
repo:{GitHubOrg}/{Repo}:pull_request
```

For an environment-gated deploy (GitHub Environments):

```
repo:{GitHubOrg}/{Repo}:environment:{EnvName}
```

For a tag push:

```
repo:{GitHubOrg}/{Repo}:ref:refs/tags/{TagName}
```

## Audiences

Always `api://AzureADTokenExchange`.

## Issuer

Always `https://token.actions.githubusercontent.com`.

## Verifying an existing credential

```bash
az ad app federated-credential list --id "$CLIENT_ID" -o table
az ad app federated-credential list --id "$CLIENT_ID" \
  --query "[].{name:name, subject:subject}" -o table
```

## Updating a credential

You can't change `name`, `issuer`, or `audiences` after creation — only `subject`:

```bash
az ad app federated-credential update \
  --id "$CLIENT_ID" \
  --federated-credential-id "$CRED_ID" \
  --parameters '{"subject": "repo:org/repo:ref:refs/heads/main"}'
```

To change anything else, delete and recreate:

```bash
az ad app federated-credential delete --id "$CLIENT_ID" --federated-credential-id "$CRED_ID"
```

## Troubleshooting AADSTS70021

```
AADSTS70021: No matching federated identity record found for presented assertion.
```

This means Azure compared the OIDC token's `sub` claim against every federated credential on the app and found no match. To debug:

1. **Get the actual token subject from the failed run.** GitHub OIDC tokens contain `sub`, `iss`, `aud`. Add this debug step temporarily:
   ```yaml
   - run: |
       echo "Workflow event: ${{ github.event_name }}"
       echo "Ref:            ${{ github.ref }}"
       echo "Expected sub:   repo:${{ github.repository }}:ref:${{ github.ref }}"
   ```
2. **Compare against the credential.** Run `az ad app federated-credential list --id $CLIENT_ID`.
3. **Common drift causes:**
   - Workflow pushes from `production` but credential is for `main`
   - Workflow is a `pull_request` event but credential is `ref:refs/heads/...`
   - Repo was renamed in GitHub; credential still has the old name
   - Org was renamed; credential still has the old org
   - Credential was created for `pull_request_target` but workflow is `pull_request`

## RBAC required for the workflow's own actions

The SP needs `Contributor` at subscription scope (for `az deployment sub create`). For modules that include `roleAssignments`, also grant `User Access Administrator` at the RG scope:

```bash
SP_OID=$(az ad sp show --id "$CLIENT_ID" --query id -o tsv)
az role assignment create \
  --assignee "$SP_OID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG_NAME"
```

`Contributor` cannot grant roles to other principals. `User Access Administrator` can.

## Cleaning up

Delete a federated credential:

```bash
az ad app federated-credential delete --id "$CLIENT_ID" --federated-credential-id "$CRED_ID"
```

Delete the SP entirely:

```bash
az ad sp delete --id "$CLIENT_ID"
az ad app delete --id "$CLIENT_ID"
```
