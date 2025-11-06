resource "azurerm_storage_account" "datalake" {
  name                             = replace("${local.name_prefix}st", "/[^a-z0-9]/", "")
  location                         = local.location
  resource_group_name              = azurerm_resource_group.lz.name
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  account_kind                     = "StorageV2"
  is_hns_enabled                   = true
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = false
  min_tls_version                  = "TLS1_2"

  blob_properties { versioning_enabled = true }
}

resource "azurerm_private_endpoint" "st_blob" {
  name                = "${azurerm_storage_account.datalake.name}-blob-pe"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = azurerm_subnet.privatelink.id
  private_service_connection {
    name                           = "blob-privlink"
    private_connection_resource_id = azurerm_storage_account.datalake.id
    subresource_names              = ["blob"]
  }
}

resource "azurerm_private_endpoint" "st_dfs" {
  name                = "${azurerm_storage_account.datalake.name}-dfs-pe"
  location            = local.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = azurerm_subnet.privatelink.id
  private_service_connection {
    name                           = "dfs-privlink"
    private_connection_resource_id = azurerm_storage_account.datalake.id
    subresource_names              = ["dfs"]
  }
}

resource "azurerm_storage_container" "bronze" { name = "bronze" storage_account_name = azurerm_storage_account.datalake.name }
resource "azurerm_storage_container" "silver" { name = "silver" storage_account_name = azurerm_storage_account.datalake.name }
resource "azurerm_storage_container" "gold"   { name = "gold"   storage_account_name = azurerm_storage_account.datalake.name }
