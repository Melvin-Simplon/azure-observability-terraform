output "app_service_url" {
  description = "Public URL of the App Service"
  value       = "https://${module.app_service.default_hostname}"
}

output "function_app_url" {
  description = "Public URL of the Function App"
  value       = "https://${module.function_app.default_hostname}"
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = module.storage.storage_account_name
}
