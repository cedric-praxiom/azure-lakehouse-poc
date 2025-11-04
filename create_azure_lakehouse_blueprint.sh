#!/bin/bash
set -euo pipefail

##############################################
# Azure Lakehouse Blueprint (Block 1/3)
# Author: Praxiom Architecture
# Description: Generates a production-ready Azure Lakehouse repository
# Notes: Reads configuration from vars.env
##############################################

# Load environment variables
if [ ! -f "./vars.env" ]; then
  echo "vars.env not found. Please create it first."
  exit 1
fi
source ./vars.env

# Base project directory
PROJECT="azure-lakehouse-blueprint"

echo "Creating project structure under ${PROJECT} ..."
mkdir -p $PROJECT/{docker,terraform,.github/workflows}

cd $PROJECT

##############################################
# Dockerfile
##############################################
cat > docker/Dockerfile <<EOF
FROM registry.access.redhat.com/ubi9/ubi

RUN dnf install -y \\
    curl unzip git jq python3-pip lsb-release ca-certificates gnupg software-properties-common \\
    && dnf clean all

RUN curl -fsSL https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip -o terraform.zip \\
    && unzip terraform.zip -d /usr/local/bin \\
    && rm terraform.zip

RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc \\
    && dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm \\
    && dnf install -y azure-cli

RUN pip3 install databricks-cli

WORKDIR /workspace
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

##############################################
# Entrypoint
##############################################
cat > docker/entrypoint.sh <<EOF
#!/bin/bash
set -e

echo "Authenticating to Azure using Managed Identity..."
az login --identity

echo "Loading secrets from Key Vault: ${KEYVAULT_NAME}"
export ARM_CLIENT_ID=\$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name "ARM-CLIENT-ID" --query value -o tsv)
export ARM_CLIENT_SECRET=\$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name "ARM-CLIENT-SECRET" --query value -o tsv)
export ARM_SUBSCRIPTION_ID=\$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name "ARM-SUBSCRIPTION-ID" --query value -o tsv)
export ARM_TENANT_ID=\$(az keyvault secret show --vault-name ${KEYVAULT_NAME} --name "ARM-TENANT-ID" --query value -o tsv)

echo "Terraform backend: ${STORAGE_TFSTATE}/${CONTAINER_TFSTATE}"
cd /workspace/terraform
terraform init -backend-config="resource_group_name=${RESOURCE_GROUP}" \\
               -backend-config="storage_account_name=${STORAGE_TFSTATE}" \\
               -backend-config="container_name=${CONTAINER_TFSTATE}" \\
               -backend-config="key=infra.tfstate"

terraform plan
echo "Terraform plan complete. Run 'terraform apply -auto-approve' manually to deploy."
EOF
chmod +x docker/entrypoint.sh

##############################################
# GitHub Actions Workflow
##############################################
cat > .github/workflows/build-and-push.yml <<EOF
name: Build and Push DevOps Container

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Login to Azure
        uses: azure/login@v2
        with:
        # connection with Service Principal (App Registration) in Microsoft Entra ID (Azure AD) and attach a federated credential that allows GitHub Actions to authenticate to Azure using OpenID Connect (OIDC)
        client-id: ${{ vars.AZURE_CLIENT_ID }}
        tenant-id: ${{ vars.AZURE_TENANT_ID }}
        subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
        enable-AzPSSession: false
        federated-token: ${{ steps.get_token.outputs.token }}

      - name: Build Docker image
        run: docker build -t ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG} ./docker

      - name: Push image to Azure Container Registry
        run: |
          az acr login --name ${ACR_NAME}
          docker push ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}

      - name: Post-Build Info
        run: echo "Image '${IMAGE_NAME}:${IMAGE_TAG}' built and pushed successfully."
EOF

echo "Block 1 completed: Docker + CI/CD scaffolding ready."

##############################################
# Azure Lakehouse Blueprint (Block 2/3)
# Terraform modules generation
##############################################

echo "Generating Terraform configuration ..."

##############################################
# Providers
##############################################
cat > terraform/providers.tf <<EOF
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.100"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
EOF

##############################################
# Variables
##############################################
cat > terraform/variables.tf <<EOF
variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
}
EOF

##############################################
# Resource Group and Identity
##############################################
cat > terraform/main.tf <<EOF
resource "azurerm_resource_group" "rg" {
  name     = "${RESOURCE_GROUP}"
  location = "${REGION}"
}

resource "azurerm_user_assigned_identity" "terraform_identity" {
  name                = "id-terraform-praxiom"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
EOF

##############################################
# Networking and Private DNS
##############################################
cat > terraform/networking.tf <<EOF
resource "azurerm_virtual_network" "vnet" {
  name                = "${VNET_NAME}"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${SUBNET_PRIVATE}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
  enforce_private_link_endpoint_network_policies = true
}

resource "azurerm_subnet" "default" {
  name                 = "snet-default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]
}

# Private DNS zones
resource "azurerm_private_dns_zone" "dns_kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone" "dns_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone" "dns_dbr" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = azurerm_resource_group.rg.name
}

# DNS links
resource "azurerm_private_dns_zone_virtual_network_link" "link_kv" {
  name                  = "link-kv"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_kv.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "link_blob" {
  name                  = "link-blob"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}
EOF

##############################################
# RBAC
##############################################
cat > terraform/rbac.tf <<EOF
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "rg_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.terraform_identity.principal_id
}

resource "azurerm_role_assignment" "rg_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.terraform_identity.principal_id
}
EOF

##############################################
# Terraform Backend
##############################################
cat > terraform/backend.tf <<EOF
resource "azurerm_storage_account" "tfstate" {
  name                     = "${STORAGE_TFSTATE}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = false
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "${CONTAINER_TFSTATE}"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
EOF

##############################################
# Key Vault
##############################################
cat > terraform/keyvault.tf <<EOF
resource "azurerm_key_vault" "kv" {
  name                        = "${KEYVAULT_NAME}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  sku_name                    = "standard"
  tenant_id                   = var.tenant_id
  soft_delete_enabled         = true
  purge_protection_enabled    = true
  enable_rbac_authorization   = true
}

resource "azurerm_private_endpoint" "pe_kv" {
  name                = "pe-keyvault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "kv-connection"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
}
EOF

##############################################
# ADLS Gen2
##############################################
cat > terraform/adls.tf <<EOF
resource "azurerm_storage_account" "adls" {
  name                     = "${STORAGE_ADLS}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
}

resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}
resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}
resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.adls.name
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "pe_adls" {
  name                = "pe-adls"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "adls-connection"
    private_connection_resource_id = azurerm_storage_account.adls.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
EOF

##############################################
# Databricks (Hybrid)
##############################################
cat > terraform/databricks.tf <<EOF
resource "azurerm_databricks_workspace" "dbr" {
  name                = "${DATABRICKS_NAME}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "premium"
  public_network_access_enabled = true
}
EOF

##############################################
# Data Factory
##############################################
cat > terraform/adf.tf <<EOF
resource "azurerm_data_factory" "adf" {
  name                = "${ADF_NAME}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
EOF

##############################################
# Log Analytics + Diagnostics
##############################################
cat > terraform/diagnostics.tf <<EOF
resource "azurerm_log_analytics_workspace" "log" {
  name                = "log-praxiom"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Example diagnostic setting for Key Vault
resource "azurerm_monitor_diagnostic_setting" "diag_kv" {
  name                       = "diag-keyvault"
  target_resource_id          = azurerm_key_vault.kv.id
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.log.id
  metric {
    category = "AllMetrics"
    enabled  = true
  }
  log {
    category = "AuditEvent"
    enabled  = true
  }
}
EOF

echo "Block 2 completed: Terraform modules generated."

##############################################
# Azure Lakehouse Blueprint (Block 3/3)
# Documentation and finalization
##############################################

##############################################
# README
##############################################
cat > README.md <<EOF
# Azure Lakehouse Blueprint

## Overview
This repository defines a secure, modular, and production-ready Azure Lakehouse foundation:

* **Storage** — ADLS Gen2 with bronze / silver / gold layers  
* **Compute** — Databricks (Premium, hybrid mode)  
* **Orchestration** — Azure Data Factory  
* **Security** — Key Vault, Managed Identity, Service Principal, OIDC, RBAC, Private Endpoints, Private DNS  
* **Observability** — Log Analytics Workspace + Diagnostic Settings  
* **Infrastructure as Code** — Terraform  
* **CI/CD Pipeline** — Docker + GitHub Actions  

## Folder Structure
\`\`\`bash
azure-lakehouse-blueprint/
├── docker/                     # DevOps container
├── terraform/                  # IaC modules (network, RBAC, data, diagnostics)
├── .github/workflows/          # CI/CD pipeline
├── README.md
└── LICENSE
\`\`\`

## Usage
1. **Edit configuration**

   Update variables in **vars.env** to match your Azure environment.

2. **Generate the repository**

   \`\`\`bash
   chmod +x create_azure_lakehouse_blueprint.sh
   ./create_azure_lakehouse_blueprint.sh
   \`\`\`

3. **Build and push DevOps image

Push to the main branch or trigger the GitHub Action manually.
The workflow builds and pushes `${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}` to your Azure Container Registry.

4. **Run Terraform manually

\`\`\`bash
az container create \
  --resource-group ${RESOURCE_GROUP} \
  --name terraform-lakehouse \
  --image ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG} \
  --registry-login-server ${ACR_NAME}.azurecr.io \
  --os-type Linux --cpu 2 --memory 4 \
  --command-line "/entrypoint.sh"
\`\`\`

Inside the container:

\`\`\`bash
terraform apply -auto-approve
\`\`\`  

Notes

All secrets are fetched from Azure Key Vault at runtime.
Managed Identity is granted Contributor + Reader on the resource group.
Only Key Vault and ADLS are privately linked; Databricks uses hybrid (restricted public) access.
Diagnostic logs are stored in the Log Analytics Workspace `log-praxiom`.
EOF

echo "Repository scaffold created successfully in $(pwd)"
echo "Remember to create and adjust vars.env before running Terraform."
echo "Done."