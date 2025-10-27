# Get details from the currently logged-in Azure CLI context
data "azurerm_client_config" "current" {}

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
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}

# --- Monitoring (LAW + App Insights)
module "monitor" {
  source              = "./modules/monitor"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  name_prefix         = "${var.project_name}-${var.env}"
}

# --- Networking (VNet, subnets, Private DNS zone)
module "networking" {
  source              = "./modules/networking"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  vnet_name           = "${var.project_name}-${var.env}-vnet"
  address_space       = var.vnet_address_space
  apps_subnet_prefix  = var.apps_subnet_prefix
  data_subnet_prefix  = var.data_subnet_prefix
}

# --- Logic App Standard (System-Assigned MI)
module "logicapp" {
  source = "./modules/logicapp"

  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  name_prefix         = "${var.project_name}-${var.env}"
}


# --- SQL Server + DB + Private Endpoint
module "sql" {
  source = "./modules/sql"

  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  name_prefix         = "${var.project_name}-${var.env}"

  admin_login    = "sqladminuser"
  admin_password = var.admin_password

  # If your module expects a subnet for the private endpoint, keep this:
  data_subnet_id = module.networking.data_subnet_id
}


# Give the current principal access to KV secrets
resource "azurerm_key_vault_access_policy" "current" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete"]
}
