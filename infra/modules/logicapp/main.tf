# Minimal empty workflow
resource "azurerm_logic_app_workflow" "la" {
  name                = "${var.name_prefix}-la"
  location            = var.location
  resource_group_name = var.resource_group_name

  identity {
    type = "SystemAssigned"
  }
}
