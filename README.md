# Azure Lakehouse POC — Full Blueprint (Downloadable Markdown)

This single Markdown contains **everything** you need:
- **Service Principal + OIDC** (GitHub → Azure Entra ID with Federated Credential)
- **Key Vault–driven CI config** (minimal repo variables)
- **GitHub Actions** workflow to build tooling Docker, push to **ACR**, create **ACI runner**
- **Docker (Red Hat UBI9)** toolchain image (Terraform + Azure CLI + Databricks CLI)
- **Terraform** landing zone: ADLS Gen2, Databricks (VNet-injected), ADF (Managed VNet), Key Vault, Private Endpoints, Private DNS
- **Scripts** to seed KV and bootstrap remote state
- **Runbook** with exact commands
- **Rationale** for design choices

> Copy blocks as-is, or use the accompanying ZIP you may have downloaded.

---
## diagram

              ┌────────────────────────────────────────────────────┐
              │                    GitHub Repo                     │
              │ (IaC + CI/CD workflows + Dockerfile + scripts)     │
              └───────────────┬────────────────────────────────────┘
                              │  OIDC (Federated Credential)
                              ▼
                   ┌────────────────────────────────────┐
                   │  Azure Entra ID (AAD)              │
                   │  App Registration                  │
                   │  ↳ Service Principal               │
                   │  ↳ Federated Cred. (OIDC→GitHub)   │
                   └────────────────────────────────────┘
                               │ issues JWT token
                               ▼
                ┌────────────────────────────────────────┐
                │ GitHub Actions Workflow                │
                │  1. Auth via OIDC (no secret)          │
                │  2. Read repo vars (KV reference)      │
                │  3. Build Docker (UBI9)                │
                │  4. Push image to ACR                  │
                │  5. Create ACI runner                  │
                └─────────────────┬──────────────────────┘
                                  │
                                  ▼
          ┌───────────────────────────────────────────────────────────┐
          │ Azure Container Registry (ACR)                            │
          │  ↳ Stores built DevOps toolchain image                    │
          └───────────────────────────────────────────────────────────┘
                                  │
                                  ▼
          ┌───────────────────────────────────────────────────────────┐
          │ Azure Container Instance (ACI Runner)                     │
          │  ↳ Runs Terraform using KV vars                           │
          │  ↳ Authenticates via Managed Identity                     │
          └───────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌────────────────────────────────────────────────────────────────────────┐
    │ Terraform Landing Zone                                                 │
    │  - Resource Group / VNet / Subnets                                     │
    │  - Key Vault (stores secrets & tfstate backend config)                 │
    │  - Storage Account (ADLS Gen2: bronze/silver/gold)                     │
    │  - Databricks Workspace (VNet-injected)                                │
    │  - Azure Data Factory (Managed VNet)                                   │
    │  - Private Endpoints + Private DNS zones                               │
    └────────────────────────────────────────────────────────────────────────┘


| Layer               | Component                                     | Purpose                                                  |
| ------------------- | --------------------------------------------- | -------------------------------------------------------- |
| **Identity & Auth** | Entra ID App (Service Principal)              | OIDC trust with GitHub; least privilege RBAC             |
| **Secrets**         | Azure Key Vault                               | Centralizes secrets & Terraform backend config           |
| **CI/CD**           | GitHub Actions                                | Builds/pushes Docker image; triggers Terraform           |
| **Container Infra** | ACR + ACI                                     | Stores and executes DevOps toolchain                     |
| **Toolchain**       | UBI9 + Terraform + Azure CLI + Databricks CLI | Provides consistent environment for IaC execution        |
| **IaC (Infra)**     | Terraform Modules                             | Creates landing zone: ADLS, Databricks, ADF, KV, PE, DNS |
| **Networking**      | Private Link + Private DNS                    | Enforces isolation & internal-only communication         |




## 0) Repository layout

```
.
├─ docker/
│  ├─ Dockerfile
│  └─ entrypoint.sh
├─ .github/workflows/
│  └─ build-push-create-aci.yml
├─ scripts/
│  ├─ 00_seed_kv_ci_settings.sh
│  └─ 01_bootstrap_tfstate_and_kv.sh
└─ terraform/
   ├─ versions.tf
   ├─ providers.tf
   ├─ locals.tf
   ├─ network.tf
   ├─ kv.tf
   ├─ storage.tf
   ├─ private_dns.tf
   ├─ datafactory.tf
   ├─ databricks.tf
   └─ outputs.tf
```

---

## 1) Seed Key Vault for **CI settings** (move almost everything to KV)

Keep only **Tenant ID**, **Client ID**, and **KV URI** in GitHub (non-secret repo variables).  
Everything else is stored as **Key Vault secrets** and read **after** OIDC login.

```bash
#!/usr/bin/env bash
set -euo pipefail
export LOCATION="westeurope"
export PLATFORM_RG="rg-lztbx"
export KV_NAME="kv-lztbx"                     # must be unique in tenant
export ACR_NAME="acrlztbx123"                  # globally unique, lowercase
export RESOURCE_GROUP="$PLATFORM_RG"
export IMAGE_NAME="redhat-devops"
export ACI_NAME="aci_lztbx-runner"
export GITHUB_OWNER="cedric-praxiom"
export GITHUB_REPO="azure-lakehouse-poc"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

az account set --subscription "$SUBSCRIPTION_ID"

az group create -n "$PLATFORM_RG" -l "$LOCATION" -o none

# Create KV (RBAC mode). For CI hosted runners, you can leave public access ON initially.
az keyvault create -n "$KV_NAME" -g "$PLATFORM_RG" -l "$LOCATION" --enable-rbac-authorization true -o none

KV_URI="https://${KV_NAME}.vault.azure.net/"

 
# --- Seed CI settings in KV ---
az keyvault secret set --vault-name "$KV_NAME" --name "SUBSCRIPTION-ID" --value "$SUBSCRIPTION_ID" >/dev/null

az keyvault secret set --vault-name "$KV_NAME" --name "LOCATION"        --value "$LOCATION"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "RESOURCE-GROUP"  --value "$RESOURCE_GROUP"  >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACR-NAME"        --value "$ACR_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE-NAME"      --value "$IMAGE_NAME"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACI-NAME"        --value "$ACI_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB-OWNER"      --value "$GITHUB_OWNER"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB-REPO"        --value "$GITHUB_REPO"        >/dev/null

echo "KV_URI=$KV_URI"
echo "Done. KV URI: https://${KV_NAME}.vault.azure.net/"
```

Or use the script:

### `scripts/00_seed_kv_ci_settings.sh`

```bash
#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail
export LOCATION="westeurope"
export PLATFORM_RG="rg-lztbx"
export KV_NAME="kv-lztbx"                     # must be unique in tenant
export ACR_NAME="acrlztbx123"                  # globally unique, lowercase
export RESOURCE_GROUP="$PLATFORM_RG"
export IMAGE_NAME="redhat-devops"
export ACI_NAME="aci_lztbx-runner"
export GITHUB_OWNER="cedric-praxiom"
export GITHUB_REPO="azure-lakehouse-poc"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

az account set --subscription "$SUBSCRIPTION_ID"

az group create -n "$PLATFORM_RG" -l "$LOCATION" -o none

# Create KV (RBAC mode). For CI hosted runners, you can leave public access ON initially.
az keyvault create -n "$KV_NAME" -g "$PLATFORM_RG" -l "$LOCATION" --enable-rbac-authorization true -o none

az keyvault update -n "$KV_NAME" --enable-rbac-authorization true

KV_URI="https://${KV_NAME}.vault.azure.net/"

 
# --- Seed CI settings in KV ---
az keyvault secret set --vault-name "$KV_NAME" --name "SUBSCRIPTION-ID" --value "$SUBSCRIPTION_ID" >/dev/null

az keyvault secret set --vault-name "$KV_NAME" --name "LOCATION"        --value "$LOCATION"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "RESOURCE-GROUP"  --value "$RESOURCE_GROUP"  >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACR-NAME"        --value "$ACR_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE-NAME"      --value "$IMAGE_NAME"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACI-NAME"        --value "$ACI_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB-OWNER"      --value "$GITHUB_OWNER"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB-REPO"        --value "$GITHUB_REPO"        >/dev/null

echo "KV_URI=$KV_URI"
echo "Done. KV URI: https://${KV_NAME}.vault.azure.net/"

```

---

## 2) Create Service Principal + Federated Credential (OIDC)

Creates an App registration (SPN) **without secrets**, and trusts your **GitHub repo/branch** via OIDC.

```bash
# ======= Fill these =======
export DISPLAY_NAME="spn-gha-oidc-poc"
export SUBSCRIPTION_ID="$(az keyvault secret show --vault-name "$KV_NAME" -n "SUBSCRIPTION-ID"  --query value -o tsv)"
export TENANT_ID="$(az account show --query tenantId -o tsv)"
export GITHUB_OWNER="$(az keyvault secret show --vault-name "$KV_NAME" -n "GITHUB-OWNER" --query id -o tsv)"            # e.g., my-org
export GITHUB_REPO="$(az keyvault secret show --vault-name "$KV_NAME" -n "GITHUB-REPO"  --query id -o tsv)"                    # e.g., azure-lakehouse-blueprint
export GITHUB_REF="refs/heads/main"            # or refs/tags/v1, etc.
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

echo "TENANT_ID=$TENANT_ID"
echo "APP_ID (Client ID) = $APP_ID"

echo "Set GitHub repo variables: AZURE_TENANT_ID=$TENANT_ID, AZURE_OIDC_CLIENT_ID=$APP_ID, KV_URI=$KV_URI"

```

**Why**: OIDC avoids long-lived secrets; federated credential scopes trust to your repo/branch.

---

## 3) GitHub repository variables (UI)

Set **repo variables** (not secrets):

- `AZURE_TENANT_ID` = your Tenant ID  
- `AZURE_OIDC_CLIENT_ID` = the App registration **APP_ID** (client ID)  
- `KV_URI` = `https://<kv-name>.vault.azure.net/`

Nothing else is required in GitHub.

---

## 4) GitHub Actions — Build Docker → Push to ACR → Create ACI runner (KV-driven)

**`.github/workflows/build-push-create-aci.yml`**
```yaml
name: build-push-create-aci (KV-driven)

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

env:
  AZURE_TENANT_ID:      ${{ vars.AZURE_TENANT_ID }}
  AZURE_OIDC_CLIENT_ID: ${{ vars.AZURE_OIDC_CLIENT_ID }}
  KV_URI:               ${{ vars.KV_URI }}  # https://<kv>.vault.azure.net/

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    # 1) Secretless OIDC login: requires tenant + client-id only
    - name: Azure login (OIDC)
      uses: azure/login@v2
      with:
        client-id:  ${{ env.AZURE_OIDC_CLIENT_ID }}
        tenant-id:  ${{ env.AZURE_TENANT_ID }}

    # 2) Pull pipeline settings from Key Vault (data-plane)
    - name: Read pipeline config from Key Vault
      run: |
        set -e
        kv="${{ env.KV_URI }}"
        kv="${kv%/}"
        get() { az keyvault secret show --id "$kv/secrets/$1" --query value -o tsv; }
        echo "SUBSCRIPTION_ID=$(get SUBSCRIPTION_ID)"       >> $GITHUB_ENV
        echo "LOCATION=$(get LOCATION)"                     >> $GITHUB_ENV
        echo "RESOURCE_GROUP=$(get RESOURCE_GROUP)"         >> $GITHUB_ENV
        echo "ACR_NAME=$(get ACR_NAME)"                     >> $GITHUB_ENV
        echo "IMAGE_NAME=$(get IMAGE_NAME)"                 >> $GITHUB_ENV
        echo "ACI_NAME=$(get ACI_NAME)"                     >> $GITHUB_ENV

    # 3) Select subscription (now that we know it)
    - name: Select subscription
      run: az account set --subscription "$SUBSCRIPTION_ID"

    # 4) Ensure RG + ACR
    - name: Ensure Resource Group
      run: az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none

    - name: Ensure ACR
      run: |
        if ! az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
          az acr create -n "$ACR_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" --sku Standard -o none
        fi
        echo "ACR_LOGIN_SERVER=$(az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" --query loginServer -o tsv)" >> $GITHUB_ENV

    # 5) Build & push tooling image (linux/amd64)
    - name: Build & push
      run: |
        az acr login --name "$ACR_NAME"
        docker buildx create --use
        docker buildx build --platform linux/amd64           -t "$ACR_LOGIN_SERVER/$IMAGE_NAME:latest"           -t "$ACR_LOGIN_SERVER/$IMAGE_NAME:${{ github.sha }}"           ./docker --push

    # 6) Ensure UAMI + ACI runner
    - name: Ensure UAMI
      run: |
        UAMI_NAME="uami-tf-runner"
        az identity show -g "$RESOURCE_GROUP" -n "$UAMI_NAME" >/dev/null 2>&1 ||           az identity create -g "$RESOURCE_GROUP" -n "$UAMI_NAME" -l "$LOCATION" -o none
        echo "UAMI_ID=$(az identity show -g $RESOURCE_GROUP -n $UAMI_NAME --query id -o tsv)" >> $GITHUB_ENV
        echo "UAMI_PRIN=$(az identity show -g $RESOURCE_GROUP -n $UAMI_NAME --query principalId -o tsv)" >> $GITHUB_ENV

    - name: Grant roles to UAMI (Contributor; add UAA only if needed)
      run: |
        SUB="/subscriptions/$SUBSCRIPTION_ID"
        az role assignment create --assignee-object-id "$UAMI_PRIN"           --assignee-principal-type ServicePrincipal           --role "Contributor" --scope "$SUB" >/dev/null || true

    - name: Create/Refresh ACI runner (ephemeral)
      run: |
        az container show -g "$RESOURCE_GROUP" -n "$ACI_NAME" >/dev/null 2>&1 &&           az container delete -g "$RESOURCE_GROUP" -n "$ACI_NAME" --yes -o none
        az container create -g "$RESOURCE_GROUP" -n "$ACI_NAME"           --image "$ACR_LOGIN_SERVER/$IMAGE_NAME:latest"           --registry-login-server "$ACR_LOGIN_SERVER"           --assign-identity "$UAMI_ID"           --cpu 2 --memory 4           --restart-policy Never           --os-type Linux           --command-line "/bin/bash"           -l "$LOCATION" -o none

    - name: How to connect
      run: |
        echo "Attach shell:"
        echo "  az container exec -g $RESOURCE_GROUP -n $ACI_NAME --exec-command "/bin/bash""
        echo "Inside ACI, run:"
        echo "  az login --identity && az account show"
        echo "  cd /work/terraform && terraform init -backend-config=backend.hcl && terraform plan"
```

---

## 5) Docker toolchain (Red Hat UBI9)

**`docker/Dockerfile`**
```Dockerfile
FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf -y update && dnf -y install     curl unzip tar gzip git jq python3 python3-pip     libicu ca-certificates procps-ng which iputils     && dnf clean all

# Azure CLI
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc &&     curl -sL https://packages.microsoft.com/config/rhel/9/prod.repo -o /etc/yum.repos.d/microsoft-prod.repo &&     dnf -y install azure-cli && dnf clean all

# Terraform
RUN dnf -y install dnf-plugins-core &&     dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo &&     dnf -y install terraform && dnf clean all

# Optional Databricks CLI + Azure Identity for later scripting
RUN pip3 install --no-cache-dir databricks azure-identity

WORKDIR /work
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
```

**`docker/entrypoint.sh`**
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "Container ready."
echo "In ACI: az login --identity && az account show"
echo "Then:   cd /work/terraform && terraform init/plan/apply"
exec "$@"
```

---

## 6) Bootstrap remote state + workload Key Vault (for Terraform inputs)

**`scripts/01_bootstrap_tfstate_and_kv.sh`**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Required envs:
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${PLATFORM_RG:?set PLATFORM_RG}"           # e.g., rg-lz-poc
: "${LOCATION:?set LOCATION}"                 # e.g., westeurope

# Optional overrides:
: "${TFSTATE_NAME:=sttf$(tr -dc a-z0-9 </dev/urandom | head -c 8)}"
: "${WORK_KV_NAME:=kv-$(tr -dc a-z0-9 </dev/urandom | head -c 12)}"
: "${UAMI_NAME:=uami-tf-runner}"

az account set --subscription "$SUBSCRIPTION_ID"

# 1) Remote state
az group create -n "$PLATFORM_RG" -l "$LOCATION" -o none
az storage account create -n "$TFSTATE_NAME" -g "$PLATFORM_RG" -l "$LOCATION"   --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2   --allow-blob-public-access false -o none
az storage container create --name tfstate --account-name "$TFSTATE_NAME" --auth-mode login -o none

cat > /work/terraform/backend.hcl <<EOF
resource_group_name  = "$PLATFORM_RG"
storage_account_name = "$TFSTATE_NAME"
container_name       = "tfstate"
key                  = "infra.tfstate"
EOF

# 2) Workload Key Vault (RBAC mode)
az keyvault create -n "$WORK_KV_NAME" -g "$PLATFORM_RG" -l "$LOCATION"   --enable-rbac-authorization true -o none

# Grant UAMI rights
UAMI_PRIN=$(az identity show -g "$PLATFORM_RG" -n "$UAMI_NAME" --query principalId -o tsv)
az role assignment create --role "Key Vault Secrets Officer"   --assignee-object-id "$UAMI_PRIN" --assignee-principal-type ServicePrincipal   --scope "$(az keyvault show -n $WORK_KV_NAME -g $PLATFORM_RG --query id -o tsv)" >/dev/null || true

# 3) Seed infra params
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "project-name" --value "lz-poc" >/dev/null
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "env"          --value "dev"     >/dev/null
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "location"     --value "$LOCATION" >/dev/null

az keyvault secret set --vault-name "$WORK_KV_NAME" --name "vnet-cidr"             --value "10.10.0.0/16" >/dev/null
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "snet-privatelink-cidr" --value "10.10.1.0/24" >/dev/null
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "snet-dbx-public-cidr"  --value "10.10.2.0/24" >/dev/null
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "snet-dbx-private-cidr" --value "10.10.3.0/24" >/dev/null

az keyvault secret set --vault-name "$WORK_KV_NAME" --name "databricks-sku"          --value "premium" >/dev/null
az keyvault secret set --vault-name "$WORK_KV_NAME" --name "databricks-no-public-ip" --value "true"    >/dev/null

echo "Bootstrap complete."
echo "TFSTATE_NAME=$TFSTATE_NAME"
echo "WORKLOAD_KV=$WORK_KV_NAME"
```

**Optional helper to seed the CI KV:**

**`scripts/00_seed_kv_ci_settings.sh`**
```bash
#!/usr/bin/env bash
set -euo pipefail
: "${PLATFORM_RG:?RG required}"
: "${KV_NAME:?KV required}"
: "${SUBSCRIPTION_ID:?SUB required}"
: "${LOCATION:?LOC required}"
: "${ACR_NAME:?ACR required}"
: "${RESOURCE_GROUP:?RG required}"
: "${IMAGE_NAME:=redhat-devops}"
: "${ACI_NAME:=tf-runner}"
az account set --subscription "$SUBSCRIPTION_ID"

echo "Seeding CI settings in KV: $KV_NAME"
az keyvault secret set --vault-name "$KV_NAME" --name "SUBSCRIPTION_ID" --value "$SUBSCRIPTION_ID" >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "LOCATION"        --value "$LOCATION"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "RESOURCE_GROUP"  --value "$RESOURCE_GROUP"  >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACR_NAME"        --value "$ACR_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE_NAME"      --value "$IMAGE_NAME"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACI_NAME"        --value "$ACI_NAME"        >/dev/null
echo "Done. KV URI: https://${KV_NAME}.vault.azure.net/"
```

---

## 7) Terraform — landing zone

**`terraform/versions.tf`**
```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.7" }
  }
}
```

**`terraform/providers.tf`**
```hcl
provider "azurerm" {
  features {}
  use_msi = true  # running inside ACI with UAMI
}
```

**`terraform/locals.tf`**
```hcl
data "azurerm_client_config" "current" {}

variable "kv_name"     { type = string }  # WORK_KV_NAME from bootstrap
variable "platform_rg" { type = string }  # RG containing that KV

data "azurerm_key_vault" "kv" {
  name                = var.kv_name
  resource_group_name = var.platform_rg
}

# Parameters from KV (no tfvars)
data "azurerm_key_vault_secret" "proj"    { name = "project-name" key_vault_id = data.azurerm_key_vault.kv.id }
data "azurerm_key_vault_secret" "env"     { name = "env"          key_vault_id = data.azurerm_key_vault.kv.id }
data "azurerm_key_vault_secret" "loc"     { name = "location"     key_vault_id = data.azurerm_key_vault.kv.id }

data "azurerm_key_vault_secret" "vnet"    { name = "vnet-cidr"             key_vault_id = data.azurerm_key_vault.kv.id }
data "azurerm_key_vault_secret" "pl"      { name = "snet-privatelink-cidr" key_vault_id = data.azurerm_key_vault.kv.id }
data "azurerm_key_vault_secret" "dp"      { name = "snet-dbx-public-cidr"  key_vault_id = data.azurerm_key_vault.kv.id }
data "azurerm_key_vault_secret" "dv"      { name = "snet-dbx-private-cidr" key_vault_id = data.azurerm_key_vault.kv.id }

data "azurerm_key_vault_secret" "dbxsku"  { name = "databricks-sku"          key_vault_id = data.azurerm_key_vault.kv.id }
data "azurerm_key_vault_secret" "dbxnp"   { name = "databricks-no-public-ip" key_vault_id = data.azurerm_key_vault.kv.id }

locals {
  proj         = data.azurerm_key_vault_secret.proj.value
  env          = data.azurerm_key_vault_secret.env.value
  location     = data.azurerm_key_vault_secret.loc.value
  name_prefix  = "${local.proj}-${local.env}"

  vnet_cidr     = data.azurerm_key_vault_secret.vnet.value
  snet_pl_cidr  = data.azurerm_key_vault_secret.pl.value
  snet_dbx_pub  = data.azurerm_key_vault_secret.dp.value
  snet_dbx_priv = data.azurerm_key_vault_secret.dv.value

  dbx_sku       = data.azurerm_key_vault_secret.dbxsku.value
  dbx_no_public = lower(data.azurerm_key_vault_secret.dbxnp.value) == "true"
}

resource "azurerm_resource_group" "lz" {
  name     = var.platform_rg
  location = local.location
}
```

**`terraform/network.tf`**
```hcl
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name_prefix}-vnet"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  address_space       = [local.vnet_cidr]
}

resource "azurerm_subnet" "privatelink" {
  name                                      = "snet-privatelink"
  resource_group_name                       = azurerm_resource_group.lz.name
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  address_prefixes                          = [local.snet_pl_cidr]
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "dbx_public" {
  name                 = "snet-dbx-public"
  resource_group_name  = azurerm_resource_group.lz.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.snet_dbx_pub]
}

resource "azurerm_subnet" "dbx_private" {
  name                 = "snet-dbx-private"
  resource_group_name  = azurerm_resource_group.lz.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.snet_dbx_priv]
}
```

**`terraform/kv.tf`**
```hcl
resource "azurerm_key_vault" "work" {
  name                          = replace("${local.name_prefix}-kv", "/[^a-z0-9-]/", "")
  location                      = local.location
  resource_group_name           = azurerm_resource_group.lz.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
}

resource "azurerm_private_endpoint" "kv" {
  name                = "${azurerm_key_vault.work.name}-pe"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = azurerm_subnet.privatelink.id
  private_service_connection {
    name                           = "kv-privlink"
    private_connection_resource_id = azurerm_key_vault.work.id
    subresource_names              = ["vault"]
  }
}
```

**`terraform/storage.tf`**
```hcl
resource "azurerm_storage_account" "datalake" {
  name                             = replace("${local.name_prefix}st", "/[^a-z0-9]/", "")
  location                         = local.location
  resource_group_name              = azurerm_resource_group.lz.name
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  account_kind                     = "StorageV2"
  is_hns_enabled                   = true
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = false
  min_tls_version                  = "TLS1_2"

  blob_properties { versioning_enabled = true }
}

resource "azurerm_private_endpoint" "st_blob" {
  name                = "${azurerm_storage_account.datalake.name}-blob-pe"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = azurerm_subnet.privatelink.id
  private_service_connection {
    name                           = "blob-privlink"
    private_connection_resource_id = azurerm_storage_account.datalake.id
    subresource_names              = ["blob"]
  }
}

resource "azurerm_private_endpoint" "st_dfs" {
  name                = "${azurerm_storage_account.datalake.name}-dfs-pe"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = azurerm_subnet.privatelink.id
  private_service_connection {
    name                           = "dfs-privlink"
    private_connection_resource_id = azurerm_storage_account.datalake.id
    subresource_names              = ["dfs"]
  }
}

resource "azurerm_storage_container" "bronze" { name = "bronze" storage_account_name = azurerm_storage_account.datalake.name }
resource "azurerm_storage_container" "silver" { name = "silver" storage_account_name = azurerm_storage_account.datalake.name }
resource "azurerm_storage_container" "gold"   { name = "gold"   storage_account_name = azurerm_storage_account.datalake.name }
```

**`terraform/private_dns.tf`**
```hcl
locals {
  zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.vaultcore.azure.net"
  ]
}

resource "azurerm_private_dns_zone" "z" {
  for_each            = toset(local.zones)
  name                = each.key
  resource_group_name = azurerm_resource_group.lz.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  for_each              = azurerm_private_dns_zone.z
  name                  = "${replace(each.key,".","-")}-link"
  private_dns_zone_name = each.value.name
  resource_group_name   = azurerm_resource_group.lz.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone_group" "kv" {
  name                  = "kv-zg"
  private_endpoint_name = azurerm_private_endpoint.kv.name
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_configs { name = "kv"  private_dns_zone_id = azurerm_private_dns_zone.z["privatelink.vaultcore.azure.net"].id }
}

resource "azurerm_private_dns_zone_group" "blob" {
  name                  = "blob-zg"
  private_endpoint_name = azurerm_private_endpoint.st_blob.name
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_configs { name = "blob" private_dns_zone_id = azurerm_private_dns_zone.z["privatelink.blob.core.windows.net"].id }
}

resource "azurerm_private_dns_zone_group" "dfs" {
  name                  = "dfs-zg"
  private_endpoint_name = azurerm_private_endpoint.st_dfs.name
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_configs { name = "dfs" private_dns_zone_id = azurerm_private_dns_zone.z["privatelink.dfs.core.windows.net"].id }
}
```

**`terraform/datafactory.tf`**
```hcl
resource "azurerm_data_factory" "adf" {
  name                           = "${local.name_prefix}-adf"
  location                       = local.location
  resource_group_name            = azurerm_resource_group.lz.name
  public_network_enabled         = false
  managed_virtual_network_enabled= true
  identity { type = "SystemAssigned" }
}

resource "azurerm_role_assignment" "adf_kv_secrets" {
  scope                = azurerm_key_vault.work.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

resource "azurerm_data_factory_managed_private_endpoint" "adf_to_dfs" {
  name               = "adf-mpe-dfs"
  data_factory_id    = azurerm_data_factory.adf.id
  target_resource_id = azurerm_storage_account.datalake.id
  subresource_name   = "dfs"
}

resource "azurerm_data_factory_managed_private_endpoint" "adf_to_kv" {
  name               = "adf-mpe-kv"
  data_factory_id    = azurerm_data_factory.adf.id
  target_resource_id = azurerm_key_vault.work.id
  subresource_name   = "vault"
}
```

**`terraform/databricks.tf`**
```hcl
resource "azurerm_databricks_access_connector" "ac" {
  name                = "${local.name_prefix}-dbx-ac"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  identity { type = "SystemAssigned" }
}

resource "azurerm_role_assignment" "ac_blob_rw" {
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.ac.identity[0].principal_id
}

resource "azurerm_databricks_workspace" "dbx" {
  name                        = "${local.name_prefix}-dbx"
  location                    = local.location
  resource_group_name         = azurerm_resource_group.lz.name
  sku                         = local.dbx_sku
  managed_resource_group_name = "${local.name_prefix}-dbx-mrg"
  public_network_access_enabled = false
  custom_parameters {
    no_public_ip        = local.dbx_no_public
    virtual_network_id  = azurerm_virtual_network.vnet.id
    public_subnet_name  = azurerm_subnet.dbx_public.name
    private_subnet_name = azurerm_subnet.dbx_private.name
  }
}
```

**`terraform/outputs.tf`**
```hcl
output "key_vault"     { value = azurerm_key_vault.work.name }
output "datalake"      { value = azurerm_storage_account.datalake.name }
output "adf"           { value = azurerm_data_factory.adf.name }
output "databricks"    { value = azurerm_databricks_workspace.dbx.name }
```

---

## 8) Runbook — exact sequence

1) **Create OIDC SPN + federated credential** (Section 1)  
2) **Seed CI Key Vault** (Section 2) and set GitHub repo variables:  
   - `AZURE_TENANT_ID`, `AZURE_OIDC_CLIENT_ID`, `KV_URI`  
3) **Run GitHub workflow** `build-push-create-aci (KV-driven)`  
4) **Attach shell** to the ACI runner and run bootstrap + Terraform:
```bash
az container exec -g <RESOURCE_GROUP> -n <ACI_NAME> --exec-command "/bin/bash"

# Inside container
az login --identity
az account set --subscription "<SUBSCRIPTION_ID>"

cd /work/scripts
export SUBSCRIPTION_ID="<SUB>"
export PLATFORM_RG="<RESOURCE_GROUP>"
export LOCATION="<LOCATION>"
bash 01_bootstrap_tfstate_and_kv.sh
# -> prints WORKLOAD_KV and TFSTATE_NAME

cd /work/terraform
export TF_VAR_kv_name="<WORKLOAD_KV_FROM_BOOTSTRAP>"
export TF_VAR_platform_rg="<RESOURCE_GROUP>"
terraform init -backend-config=backend.hcl
terraform plan
terraform apply -auto-approve
terraform output
```

---

## 9) Rationale (why these choices)

- **OIDC + Federated Credential**: secretless CI → Azure; trust scoped to repo/branch.  
- **KV-driven CI config**: GitHub holds only non-secret bootstrap; rest managed centrally in KV.  
- **ACI + UAMI**: ephemeral, secretless runtime for Terraform; least privilege via RBAC.  
- **Private Endpoints + Private DNS**: real prod-like network isolation.  
- **Databricks VNet-injected (no public IP)** + **Access Connector**: aligns with Unity Catalog & secure external locations.  
- **ADF Managed VNet + MPE**: private data movement without self-hosted IR.  
- **Terraform remote state (StorageV2)**: team-safe state; versioned blobs.

---

**That's it.** Paste these files into your repo or use the ZIP. Happy shipping!
