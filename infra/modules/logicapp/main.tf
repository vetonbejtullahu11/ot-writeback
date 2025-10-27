# Random suffix to guarantee global uniqueness
resource "random_string" "la_suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Logic App (Consumption)
resource "azurerm_logic_app_workflow" "la" {
  name                = "${var.name_prefix}-la-${random_string.la_suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name

  identity {
    type = "SystemAssigned"
  }

  tags = {
    appinsights_connection = var.appi_connection_string
  }
}
