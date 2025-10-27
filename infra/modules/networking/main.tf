# Dummy networking module for CI

variable "address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "apps_subnet_prefix" {
  type    = string
  default = "10.0.1.0/24"
}

variable "data_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}

output "vnet_id" {
  value = "dummy-vnet-id"
}

output "apps_subnet_id" {
  value = "dummy-apps-subnet-id"
}

output "data_subnet_id" {
  value = "dummy-data-subnet-id"
}

output "sql_private_dns_zone_id" {
  value = "dummy-sql-private-dns-zone-id"
}
