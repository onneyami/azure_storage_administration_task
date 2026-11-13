resource "azurerm_resource_group" "lab_rg" {
  name     = "rg-storage-lab"
  location = var.location
}