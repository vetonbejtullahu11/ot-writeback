output "vnet_id" {
  description = "VNet resource ID"
  value       = azurerm_virtual_network.vnet.id
}

output "apps_subnet_id" {
  description = "Apps subnet ID"
  value       = azurerm_subnet.apps.id
}

output "data_subnet_id" {
  description = "Data subnet ID"
  value       = azurerm_subnet.data.id
}

output "sql_private_dns_zone_id" {
  description = "Private DNS zone id for SQL privatelink (or null if not created)"
  value       = try(azurerm_private_dns_zone.sql[0].id, null)
}
