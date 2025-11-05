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

export KV_URI="https://${KV_NAME}.vault.azure.net/"

 
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
