variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string } # e.g., "ot-writeback-dev"
variable "kv_id" { type = string }       # existing Key Vault id to store secrets
variable "kv_name" { type = string }     # for secret naming convention
variable "data_subnet_id" { type = string }
variable "sql_private_dns_zone_id" { type = string } # from networking module (can be null)
