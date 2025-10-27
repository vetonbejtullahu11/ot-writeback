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

# Optional: only include this if you want the output for it
# resource "azurerm_private_dns_zone" "sql" {
#   name                = "privatelink.database.windows.net"
#   resource_group_name = var.resource_group_name
# }
