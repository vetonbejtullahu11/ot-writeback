output "resource_group_name" { value = azurerm_resource_group.rg.name }
output "key_vault_name" { value = azurerm_key_vault.kv.name }

output "sql_fqdn" { value = module.sql.sql_server_fqdn }
output "db_name" { value = module.sql.database_name }
output "kv_uri" { value = azurerm_key_vault.kv.vault_uri }
output "mi_principal_id" { value = module.logicapp.mi_principal_id }

output "app_insights_connection_string" {
  value     = module.monitor.appi_connection_string
  sensitive = true
}

