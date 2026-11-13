# Fetching existing resource group
data "azurerm_resource_group" "lab" {
  name = var.rg_name
}