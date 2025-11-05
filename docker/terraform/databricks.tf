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
