resource "azurerm_storage_account" "lab_sa" {
  name                     = "stlab${random_string.suffix.result}"
  resource_group_name      = data.azurerm_resource_group.lab.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = true

  static_website {
    index_document = "index.html"
  }

  network_rules {
    default_action             = "Allow"
    ip_rules                   = []
    virtual_network_subnet_ids = [azurerm_subnet.lab_subnet.id]
  }

  blob_properties {
    versioning_enabled = true
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 1. Static website
resource "azurerm_storage_blob" "index_html" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.lab_sa.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  source                 = "src/index.html"
}

# 2. File share
resource "azurerm_storage_share" "lab_share" {
  name                 = "labshare"
  storage_account_name = azurerm_storage_account.lab_sa.name
  quota                = 5
}

resource "azurerm_storage_container" "private_container" {
  name                  = "private-data"
  storage_account_name  = azurerm_storage_account.lab_sa.name
  container_access_type = "private"
}

resource "time_offset" "sas_expiry" {
  offset_hours = 1
}

data "azurerm_storage_account_blob_container_sas" "lab_sas" {
  connection_string = azurerm_storage_account.lab_sa.primary_connection_string
  container_name    = azurerm_storage_container.private_container.name
  https_only        = true

  start  = time_offset.sas_expiry.base_rfc3339
  expiry = time_offset.sas_expiry.rfc3339

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = true
  }
}

