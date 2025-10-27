output "mi_principal_id" {
  description = "Managed Identity principal id (null for Consumption)"
  value       = try(azurerm_logic_app_standard.la.identity[0].principal_id, try(azurerm_logic_app_workflow.la.identity[0].principal_id, null))
}
