output "key_vault"     { value = azurerm_key_vault.work.name }
output "datalake"      { value = azurerm_storage_account.datalake.name }
output "adf"           { value = azurerm_data_factory.adf.name }
output "databricks"    { value = azurerm_databricks_workspace.dbx.name }
