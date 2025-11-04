provider "azurerm" {
  features {}
  use_msi = true  # running inside ACI with UAMI
}
