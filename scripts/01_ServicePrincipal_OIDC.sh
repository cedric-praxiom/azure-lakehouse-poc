# ======= Fill these =======
export LOCATION="westeurope"
export PLATFORM_RG="rg-lztbx"
export KV_NAME="kv-lztbx"       
export KV_URI="https://${KV_NAME}.vault.azure.net/"            
export ACR_NAME="acrlztbx123"                
export RESOURCE_GROUP="$PLATFORM_RG"
export IMAGE_NAME="redhat-devops"
export ACI_NAME="aci_lztbx-runner"
export GITHUB_OWNER="cedric-praxiom"
export GITHUB_REPO="azure-lakehouse-poc"
export DISPLAY_NAME="spn-gha-oidc-poc"
export SUBSCRIPTION_ID="$(az keyvault secret show --vault-name "$KV_NAME" -n "SUBSCRIPTION-ID"  --query value -o tsv)"
export TENANT_ID="$(az account show --query tenantId -o tsv)"
export GITHUB_OWNER="$(az keyvault secret show --vault-name "$KV_NAME" -n "GITHUB-OWNER" --query value -o tsv)"         
export GITHUB_REPO="$(az keyvault secret show --vault-name "$KV_NAME" -n "GITHUB-REPO"  --query value -o tsv)"               
export GITHUB_REF="refs/heads/main"      
## ==========================

#az keyvault secret show --name "GITHUB-OWNER" --vault-name "keyvaultname" --query value -o tsv   

az account set --subscription "$SUBSCRIPTION_ID"

# App registration (clientId/appId)
APP_ID=$(az ad app create --display-name "$DISPLAY_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)



# Service Principal (object used by RBAC)
SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

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
SUB_SCOPE="/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "Contributor" --scope "$SUB_SCOPE" >/dev/null || true
# Only if your pipelines will create RBAC assignments:
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "User Access Administrator" --scope "$SUB_SCOPE" >/dev/null || true

# Give the SPN read rights on KV secrets
SCOPE_KV=$(az keyvault show -n "$KV_NAME" -g "$PLATFORM_RG" --query id -o tsv)
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "Key Vault Secrets User" --scope "$SCOPE_KV" >/dev/null || true

az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal   --role "AcrPull" --scope "$SCOPE_KV" >/dev/null || true
echo $SP_OBJECT_ID
  echo "TENANT_ID=$TENANT_ID"
echo "APP_ID (Client ID) = $APP_ID"

echo "Set GitHub repo variables: AZURE_TENANT_ID=$TENANT_ID, AZURE_OIDC_CLIENT_ID=$APP_ID, KV_URI=$KV_URI"