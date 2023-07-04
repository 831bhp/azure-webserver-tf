output "load_balancer_public_ip_address" {
  value = azurerm_public_ip.webserver_public_ip.ip_address
}
output "resource_group_name" {
  value = azurerm_resource_group.webserver_rg.name
}
