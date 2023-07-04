output "resource_group_name" {
  value = azurerm_resource_group.mediawiki_rg.name
}

output "public_ip_address" {
  value = azurerm_linux_virtual_machine.mediawiki_vm.public_ip_address
}

output "local_file" {
  value     = local_file.linux_key.filename
}
