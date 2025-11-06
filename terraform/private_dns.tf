locals {
  zones = [
    "privatelink.blob.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.vaultcore.azure.net"
  ]
}

resource "azurerm_private_dns_zone" "z" {
  for_each            = toset(local.zones)
  name                = each.key
  resource_group_name = azurerm_resource_group.lz.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  for_each              = azurerm_private_dns_zone.z
  name                  = "${replace(each.key,".","-")}-link"
  private_dns_zone_name = each.value.name
  resource_group_name   = azurerm_resource_group.lz.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_zone_group" "kv" {
  name                  = "kv-zg"
  private_endpoint_name = azurerm_private_endpoint.kv.name
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_configs { name = "kv"  private_dns_zone_id = azurerm_private_dns_zone.z["privatelink.vaultcore.azure.net"].id }
}

resource "azurerm_private_dns_zone_group" "blob" {
  name                  = "blob-zg"
  private_endpoint_name = azurerm_private_endpoint.st_blob.name
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_configs { name = "blob" private_dns_zone_id = azurerm_private_dns_zone.z["privatelink.blob.core.windows.net"].id }
}

resource "azurerm_private_dns_zone_group" "dfs" {
  name                  = "dfs-zg"
  private_endpoint_name = azurerm_private_endpoint.st_dfs.name
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_configs { name = "dfs" private_dns_zone_id = azurerm_private_dns_zone.z["privatelink.dfs.core.windows.net"].id }
}
