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
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE_NAME"      --value "$IMAGE_NAME"      >/devnull 2>&1 || true
az keyvault secret set --vault-name "$KV_NAME" --name "IMAGE_NAME"      --value "$IMAGE_NAME"      >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name "ACI_NAME"        --value "$ACI_NAME"        >/dev/null
echo "Done. KV URI: https://${KV_NAME}.vault.azure.net/"
