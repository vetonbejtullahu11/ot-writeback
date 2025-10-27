variable "resource_group_name" {
  description = "Resource group for the Logic App"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used in the Logic App name"
  type        = string
}

variable "application_insights_connection_string" {
  description = "App Insights connection string (optional)"
  type        = string
  default     = null
}
