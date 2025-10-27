output "mi_principal_id" {
  value = azurerm_logic_app_workflow.la.identity[0].principal_id
}
