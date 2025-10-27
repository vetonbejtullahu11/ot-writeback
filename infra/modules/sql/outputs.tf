output "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name"
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "database_name" {
  description = "SQL database name"
  value       = azurerm_mssql_database.db.name
}
