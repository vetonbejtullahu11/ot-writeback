variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "address_space" {
  type = list(string)
}

variable "apps_subnet_name" {
  type    = string
  default = "apps"
}

variable "apps_subnet_prefix" {
  type = string
}

variable "data_subnet_name" {
  type    = string
  default = "data"
}

variable "data_subnet_prefix" {
  type = string
}

variable "enable_private_dns_sql" {
  type    = bool
  default = true
}
