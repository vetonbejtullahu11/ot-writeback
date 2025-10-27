
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "SQL Server admin password for the dev environment"
}


variable "location" {
  type    = string
  default = "westeurope"
}

variable "project_name" {
  type    = string
  default = "ot-writeback"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "vnet_address_space" { type = list(string) }
variable "apps_subnet_prefix" { type = string }
variable "data_subnet_prefix" { type = string }
