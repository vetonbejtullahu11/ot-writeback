output "vnet_id" { value = azurerm_virtual_network.vnet.id }
output "apps_subnet_id" { value = azurerm_subnet.apps.id }
output "data_subnet_id" { value = azurerm_subnet.data.id }
output "sql_private_dns_zone_id" {
  value       = try(azurerm_private_dns_zone.sql[0].id, null)
  description = "Private DNS zone id for privatelink.database.windows.net (if enabled)."
}
