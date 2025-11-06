#!/usr/bin/env bash
set -euo pipefail
set -a           
source vars.env 
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> vars.env
export KV_URI="https://${KV_NAME}.vault.azure.net/"
echo "KV_URI=$KV_URI" >> vars.env
set +a          

az account set --subscription "$SUBSCRIPTION_ID"

# Create the resource group for the CI factory
az group create -n "$PLATFORM_RG" -l "$LOCATION" -o none

# Create KV (RBAC mode). For CI hosted runners, you can leave public access ON initially.
az keyvault create -n "$KV_NAME" -g "$PLATFORM_RG" -l "$LOCATION" --enable-rbac-authorization true -o none

# --- Seed CI settings in KV ---
az keyvault secret set --vault-name "$KV_NAME" --name "SUBSCRIPTION-ID" --value "$SUBSCRIPTION_ID" >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "LOCATION"        --value "$LOCATION"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "RESOURCE-GROUP"  --value "$RESOURCE_GROUP"  >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACR-NAME"        --value "$ACR_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE-NAME"      --value "$IMAGE_NAME"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACI-NAME"        --value "$ACI_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB-OWNER"      --value "$GITHUB_OWNER"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB-REPO"        --value "$GITHUB_REPO"        >/dev/null

echo "Done. KV URI: $KV_URI"
