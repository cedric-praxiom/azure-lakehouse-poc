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
