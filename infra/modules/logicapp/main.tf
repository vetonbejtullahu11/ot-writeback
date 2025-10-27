variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }

# Minimal empty workflow
resource "azurerm_logic_app_workflow" "la" {
  name                = "${var.name_prefix}-la"
  location            = var.location
  resource_group_name = var.resource_group_name

  definition = jsonencode({
    "$schema"        = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
    "contentVersion" = "1.0.0.0"
    "parameters"     = {}
    "triggers"       = {}
    "actions"        = {}
    "outputs"        = {}
  })

  identity {
    type = "SystemAssigned"
  }
}
