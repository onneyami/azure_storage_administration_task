output "static_website_url" {
    value = azurerm_storage_account.lab_sa.primary_web_endpoint
}

output "vm_public_ip" {
    value = azurerm_linux_virtual_machine.lab_vm.public_ip_address
}

output "sas_url_example" {
    value = "https://${azurerm_storage_account.lab_sa.name}.blob.core.windows.net/${azurerm_storage_container.private_container.name}/test.txt${data.azurerm_storage_account_blob_container_sas.lab_sas.sas}"
    sensitive = true
}

output "mount_command_for_vm" {
    value = <<EOF
sudo mount -t cifs //${azurerm_storage_account.lab_sa.name}.file.core.windows.net/${azurerm_storage_share.lab_share.name} /mnt/labshare -o vers=3.0,username=${azurerm_storage_account.lab_sa.name},password=${azurerm_storage_account.lab_sa.primary_access_key},dir_mode=0777,file_mode=0777,serverino
EOF
  sensitive = true
}