output "law_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.app.connection_string
  sensitive = true
}

output "func_insights_connection_string" {
  value     = azurerm_application_insights.func.connection_string
  sensitive = true
}
