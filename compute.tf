resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vnet-storage-lab"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
}

resource "azurerm_subnet" "lab_subnet" {
  name                 = "snet-storage-lab"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_public_ip" "lab_pip" {
  name                = "pip-storage-lab"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "lab_nic" {
  name                = "nic-storage-lab"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab_pip.id
  }
}

resource "azurerm_linux_virtual_machine" "lab_vm" {
  name                            = "vm-storage-lab"
  resource_group_name             = azurerm_resource_group.lab_rg.name
  location                        = azurerm_resource_group.lab_rg.location
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  admin_password                  = "P@ssw0rd1234Lab!" # For test lab, in prod use SSH
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.lab_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # Cloud-init installation cifs-utils
  custom_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y cifs-utils
              mkdir -p /mnt/labshare
              EOF
  )
}