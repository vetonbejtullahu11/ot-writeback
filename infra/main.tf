# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-${var.env}-rg"
  location = var.location
}

# Key Vault (name must be globally unique, alphanumeric and hyphens)
resource "azurerm_key_vault" "kv" {
  name                = lower(replace("${var.project_name}-${var.env}-kv", "/[^a-zA-Z0-9-]/", ""))
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}
