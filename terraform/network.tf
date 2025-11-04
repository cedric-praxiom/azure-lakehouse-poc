resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name_prefix}-vnet"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  address_space       = [local.vnet_cidr]
}

resource "azurerm_subnet" "privatelink" {
  name                                      = "snet-privatelink"
  resource_group_name                       = azurerm_resource_group.lz.name
  virtual_network_name                      = azurerm_virtual_network.vnet.name
  address_prefixes                          = [local.snet_pl_cidr]
  private_endpoint_network_policies_enabled = false
}

resource "azurerm_subnet" "dbx_public" {
  name                 = "snet-dbx-public"
  resource_group_name  = azurerm_resource_group.lz.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.snet_dbx_pub]
}

resource "azurerm_subnet" "dbx_private" {
  name                 = "snet-dbx-private"
  resource_group_name  = azurerm_resource_group.lz.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.snet_dbx_priv]
}
