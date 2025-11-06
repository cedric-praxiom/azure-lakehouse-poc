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
