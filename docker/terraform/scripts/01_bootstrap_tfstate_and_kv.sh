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
