# Get details from the currently logged-in Azure CLI context
data "azurerm_client_config" "current" {}

# Maintain state when moving inline Key Vault resource into module
moved {
  from = azurerm_key_vault.kv
  to   = module.keyvault.azurerm_key_vault.this
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-${var.env}-rg"
  location = var.location
}

# Key Vault
module "keyvault" {
  source              = "./modules/keyvault"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  name_prefix         = "${var.project_name}-${var.env}"
  tenant_id           = data.azurerm_client_config.current.tenant_id
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

  resource_group_name                    = azurerm_resource_group.rg.name
  location                               = var.location
  name_prefix                            = "${var.project_name}-${var.env}"
  application_insights_connection_string = module.monitor.appi_connection_string
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
  data_subnet_id      = module.networking.data_subnet_id
  private_dns_zone_id = module.networking.sql_private_dns_zone_id
}


# Give the current principal access to KV secrets
resource "azurerm_key_vault_access_policy" "current" {
  key_vault_id = module.keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete"]
}
