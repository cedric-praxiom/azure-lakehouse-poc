# ======= Fill these =======
export DISPLAY_NAME="spn-gha-oidc-poc"
export SUBSCRIPTION_ID="(az account show --query id --output tsv)"
export TENANT_ID="$(az account show --query tenantId -o tsv)"
export GITHUB_OWNER="<org-or-user>"            # e.g., my-org
export GITHUB_REPO="<repo>"                    # e.g., azure-lakehouse-blueprint
export GITHUB_REF="refs/heads/main"            # or refs/tags/v1, etc.
# ==========================

az keyvault secret show --name "GITHUB_OWNER" --vault-name "keyvaultname" --query value -o tsv   

az account set --subscription "$SUBSCRIPTION_ID"

# App registration (clientId/appId)
APP_ID=$(az ad app create --display-name "$DISPLAY_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
echo "APP_ID=$APP_ID"

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

echo "TENANT_ID=$TENANT_ID"
echo "APP_ID (Client ID) = $APP_ID"