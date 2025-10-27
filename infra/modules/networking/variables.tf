variable "resource_group_name" {
  description = "Resource group where the VNet and subnets will be created"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_name" {
  description = "Virtual network name"
  type        = string
}

variable "address_space" {
  description = "VNet address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "apps_subnet_prefix" {
  description = "CIDR for the apps subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "data_subnet_prefix" {
  description = "CIDR for the data subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "create_sql_private_dns_zone" {
  description = "Whether to create the privatelink.database.windows.net zone"
  type        = bool
  default     = true
}
