terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# TODO (1/2) : créer un azurerm_storage_account dédié à la Function App
#
# La Function App a besoin d'un storage account propre (obligatoire Azure).
# Ce storage est SÉPARÉ du storage métier du module storage/.
#
# Nom attendu : "stfn${replace(var.owner, "-", "")}"
# Tier        : Standard, LRS, TLS 1.2
# Tags        : merge(var.tags, { purpose = "function-storage" })
#
# Documentation : https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account

resource "azurerm_storage_account" "fn_storage" {
  name                     = "stfn${replace(var.owner, "-", "")}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

# TODO (2/2) : créer un azurerm_linux_function_app
#
# Nom attendu    : "fn-${var.owner}-tf"
# Plan           : var.service_plan_id
# Storage        : azurerm_storage_account.fn_storage.name + primary_access_key
# HTTPS only     : true
# Runtime        : Python 3.11
#
# Documentation : https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_function_app

resource "azurerm_linux_function_app" "fn" {
  name                       = "fn-${var.owner}-tf"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = var.service_plan_id
  storage_account_name       = azurerm_storage_account.fn_storage.name
  storage_account_access_key = azurerm_storage_account.fn_storage.primary_access_key
  https_only                 = true
  site_config {
    application_stack {
      python_version = 3.11
    }
    health_check_path                 = "/api/http_trigger"
    health_check_eviction_time_in_min = 10
  }
  tags = var.tags
}
