variable "resource_group_name" {
  description = "Resource group in which to create the Key Vault"
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used when naming the Key Vault (env/project)"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID for the Key Vault"
  type        = string
}

variable "sku_name" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
}

variable "purge_protection_enabled" {
  description = "Whether purge protection is enabled on the Key Vault"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention window (days)"
  type        = number
  default     = 7
}
