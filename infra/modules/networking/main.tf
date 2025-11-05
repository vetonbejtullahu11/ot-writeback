resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
}

resource "azurerm_subnet" "apps" {
  name                 = var.apps_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.apps_subnet_prefix]
}

resource "azurerm_subnet" "data" {
  name                 = var.data_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.data_subnet_prefix]
}

resource "azurerm_private_dns_zone" "sql" {
  count               = var.create_sql_private_dns_zone ? 1 : 0
  name                = var.sql_private_dns_zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  count                 = var.create_sql_private_dns_zone ? 1 : 0
  name                  = "${var.vnet_name}-sql-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}
