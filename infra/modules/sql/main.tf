resource "azurerm_mssql_server" "sql" {
  name                         = "${var.name_prefix}-sql"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.admin_login
  administrator_login_password = var.admin_password
}

resource "azurerm_mssql_database" "db" {
  name                                = "${var.name_prefix}-db"
  server_id                           = azurerm_mssql_server.sql.id
  sku_name                            = "S0"
  zone_redundant                      = false
  collation                           = "SQL_Latin1_General_CP1_CI_AS"
  transparent_data_encryption_enabled = true
}

resource "azurerm_private_endpoint" "sql" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "${var.name_prefix}-sql-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id

  private_service_connection {
    name                           = "${var.name_prefix}-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.sql.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id == null ? [] : [var.private_dns_zone_id]
    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }
}
