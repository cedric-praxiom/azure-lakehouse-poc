set -a
export SUBSCRIPTION_ID="$(az keyvault secret show --vault-name "$KV_NAME" -n "SUBSCRIPTION-ID"  --query value -o tsv)"
export TENANT_ID="$(az account show --query tenantId -o tsv)"
export GITHUB_OWNER="$(az keyvault secret show --vault-name "$KV_NAME" -n "GITHUB-OWNER" --query value -o tsv)"         
export GITHUB_REPO="$(az keyvault secret show --vault-name "$KV_NAME" -n "GITHUB-REPO"  --query value -o tsv)"               
export GITHUB_REF="refs/heads/main"      
export SUB_SCOPE="/subscriptions/$SUBSCRIPTION_ID"
export SCOPE_KV=$(az keyvault show -n "$KV_NAME" -g "$PLATFORM_RG" --query id -o tsv)
# App registration (clientId/appId)
export APP_ID=$(az ad app create --display-name "$SPN_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
# Service Principal (object used by RBAC)
export SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
export APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
set +a

#az keyvault secret show --name "GITHUB-OWNER" --vault-name "keyvaultname" --query value -o tsv   

#az account set --subscription "$SUBSCRIPTION_ID"

# Federated credential (trust only this repo/branch)
cat > federated-credential.json <<'JSON'
{
  "name": "github-main-oidc",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<GITHUB_OWNER>/<GITHUB_REPO>:ref:<GITHUB_REF>",
  "description": "Trust GitHub Actions OIDC for this repo/branch",
  "audiences": [ "api://AzureADTokenExchange" ]
}
JSON
sed -i.bak "s#<GITHUB_OWNER>#$GITHUB_OWNER#g" federated-credential.json
sed -i.bak "s#<GITHUB_REPO>#$GITHUB_REPO#g" federated-credential.json
sed -i.bak "s#<GITHUB_REF>#$GITHUB_REF#g" federated-credential.json

az ad app federated-credential create --id "$APP_OBJECT_ID" --parameters @federated-credential.json

# Grant least-priv on subscription (narrow later to RG if desired)

az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "Contributor" --scope "$SUB_SCOPE" >/dev/null || true
# Only if your pipelines will create RBAC assignments:
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "User Access Administrator" --scope "$SUB_SCOPE" >/dev/null || true

# Give the SPN read rights on KV secrets

az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "Key Vault Secrets User" --scope "$SCOPE_KV" >/dev/null || true
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "AcrPull" --scope "$SCOPE_KV" >/dev/null || true

echo "SP ID : $SP_OBJECT_ID"
echo "TENANT_ID=$TENANT_ID"
echo "APP_ID (Client ID) = $APP_ID"

echo "Set GitHub repo variables: AZURE_TENANT_ID=$TENANT_ID, AZURE_OIDC_CLIENT_ID=$APP_ID, KV_URI=$KV_URI"