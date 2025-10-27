variable "resource_group_name" {
  description = "Resource group for monitoring resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for LAW and App Insights names"
  type        = string
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
}

variable "retention_days" {
  description = "Data retention for Log Analytics (days)"
  type        = number
  default     = 30
}

variable "application_insights_application_type" {
  description = "App Insights application type"
  type        = string
  default     = "web"
}
