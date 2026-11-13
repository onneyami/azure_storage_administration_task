resource "azurerm_storage_account" "lab_sa" {
  name                     = "stlab${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.lab_rg.name
  location                 = azurerm_resource_group.lab_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Simulation Break / Fix: Blob is available publicly with requered private
  allow_nested_items_to_be_public = true

  static_website {
    index_document = "index.html"
  }

  # Simulation Break / Fix: Storage firewall denying the client
  network_rules {
    default_action             = "Allow" # For simulation should be replaced by "Deny"
    ip_rules                   = []      # There is possible to implement your public ip ranges
    virtual_network_subnet_ids = [azurerm_subnet.lab_subnet.id]
  }

  blob_properties {
    versioning_enabled = true # Publish the site version
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Publishing static website
resource "azurerm_storage_blob" "index_html" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.lab_sa.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  source                 = "src/index.html"
}

# Creating file share
resource "azurerm_storage_share" "lab_share" {
  name                 = "labshare"
  storage_account_name = azurerm_storage_account.lab_sa.name
  quota                = 5
}

# Private container with SAS
resource "azurerm_storage_container" "private_container" {
  name                  = "private-data"
  storage_account_name  = azurerm_storage_account.lab_sa.name
  container_access_type = "private" # Simulation Break: changing to "blob" make public access
}

resource "time_offset" "sas_expiry" {
  offset_hours = 1 # SAS works only 1 hour
}

data "azurerm_storage_account_blob_container_sas" "lab_sas" {
  connection_string = azurerm_storage_account.lab_sa.primary_connection_string
  container_name    = azurerm_storage_container.private_container.name
  https_only        = true

  start  = timestamp()
  expiry = time_offset.sas_expiry.expiration

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = true
  }
}