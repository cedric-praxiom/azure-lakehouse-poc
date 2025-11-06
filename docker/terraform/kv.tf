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
