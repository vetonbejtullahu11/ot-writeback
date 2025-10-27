output "sql_server_fqdn" { value = azurerm_mssql_server.sql.fully_qualified_domain_name }
output "database_name" { value = azurerm_mssql_database.db.name }
