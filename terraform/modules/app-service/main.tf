terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-${var.owner}-tf"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = var.service_plan_id
  https_only          = true
  site_config {
    minimum_tls_version = "1.2"
    application_stack {
      python_version = 3.11
    }
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 10
  }
  tags = var.tags
}
