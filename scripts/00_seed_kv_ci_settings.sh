#!/usr/bin/env bash
set -euo pipefail
: "${PLATFORM_RG:rg_lztbx}"
: "${KV_NAME:kv_lztbx}"
: "${SUBSCRIPTION_ID:}"
: "${LOCATION:westeurope}"
: "${ACR_NAME:acr_lztbx}"
: "${RESOURCE_GROUP:rg_lztbx}"
: "${IMAGE_NAME:=redhat-devops}"
: "${ACI_NAME:=lztbx-runner}"
: "${GITHUB_OWNER:cedric-praxiom}"
: "${GITHUB_REPO:azure-lakehouse-poc}"

export KV_NAME-"kv_lztbx"

SUBSCRIPTION_ID=$(az account show --query id --output tsv)
az account set --subscription "$SUBSCRIPTION_ID"

echo "Seeding CI settings in KV: $KV_NAME"
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB_OWNER" --value "$GITHUB_OWNER" >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "GITHUB_REPO"  --value "$GITHUB_REPO"  >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "SUBSCRIPTION_ID" --value "$SUBSCRIPTION_ID" >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "LOCATION"        --value "$LOCATION"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "RESOURCE_GROUP"  --value "$RESOURCE_GROUP"  >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACR_NAME"        --value "$ACR_NAME"        >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE_NAME"      --value "$IMAGE_NAME"      >/devnull 
az keyvault secret set --vault-name "$KV_NAME" --name "ACI_NAME"        --value "$ACI_NAME"        >/dev/null

echo "Done. KV URI: https://${KV_NAME}.vault.azure.net/"
