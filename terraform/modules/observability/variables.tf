variable "owner" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "app_service_id" { type = string }
variable "function_app_id" { type = string }
variable "storage_account_id" { type = string }

variable "app_service_url" { type = string }
variable "function_app_url" { type = string }

variable "alert_email" { type = string }
