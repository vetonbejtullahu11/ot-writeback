variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "vnet_name" { type = string }
variable "address_space" { type = list(string) }
variable "apps_subnet_prefix" { type = string }
variable "data_subnet_prefix" { type = string }
variable "apps_subnet_name" {
  type    = string
  default = "apps"
}

variable "data_subnet_name" {
  type    = string
  default = "data"
}

variable "create_sql_private_dns_zone" {
  description = "Whether to create a private DNS zone for privatelink.database.windows.net"
  type        = bool
  default     = true
}

variable "sql_private_dns_zone_name" {
  description = "Name of the SQL private DNS zone"
  type        = string
  default     = "privatelink.database.windows.net"
}
