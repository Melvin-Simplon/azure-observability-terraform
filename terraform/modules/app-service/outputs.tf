output "default_hostname" {
  value = azurerm_linux_web_app.app.default_hostname
}

output "app_service_id" {
  value = azurerm_linux_web_app.app.id
}
