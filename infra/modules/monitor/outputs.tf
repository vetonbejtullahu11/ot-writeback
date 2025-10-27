output "law_id" {
  description = "Log Analytics Workspace ID"
  value       = azurerm_log_analytics_workspace.law.id
}

output "appi_id" {
  description = "Application Insights resource ID"
  value       = azurerm_application_insights.appi.id
}

output "appi_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.appi.connection_string
  sensitive   = true
}
