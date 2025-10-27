variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "name_prefix"         { type = string }
variable "admin_login"         { type = string }
variable "admin_password"      { type = string, sensitive = true }

resource "azurerm_mssql_server" "sql" {
  name                         = "${var.name_prefix}-sql"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.admin_login
  administrator_login_password = var.admin_password
}

resource "azurerm_mssql_database" "db" {
  name           = "${var.name_prefix}-db"
  server_id      = azurerm_mssql_server.sql.id
  sku_name       = "S0"
  zone_redundant = false
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  transparent_data_encryption_enabled = true
}
