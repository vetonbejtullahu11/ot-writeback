output "law_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "appi_id" {
  value = azurerm_application_insights.appi.id
}

output "appi_connection_string" {
  value     = azurerm_application_insights.appi.connection_string
  sensitive = true
}
