variable "resource_group_name" {
  description = "Resource group for SQL resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used when naming SQL resources"
  type        = string
}

variable "data_subnet_id" {
  description = "Subnet ID for SQL Private Endpoint (data subnet)"
  type        = string
}

variable "enable_private_endpoint" {
  description = "Whether to create a private endpoint for the SQL server"
  type        = bool
  default     = true
}

variable "private_dns_zone_id" {
  description = "Private DNS zone id for privatelink.database.windows.net (can be null to skip link)"
  type        = string
  default     = null
}

variable "admin_login" {
  description = "SQL admin login name"
  type        = string
  default     = "sqladminuser"
}

variable "admin_password" {
  description = "SQL admin password"
  type        = string
  sensitive   = true
}

variable "key_vault_id" {
  description = "Key Vault resource ID to store SQL admin password (optional)"
  type        = string
  default     = null
}
