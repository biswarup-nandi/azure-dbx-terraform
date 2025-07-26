terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    databricks = {
      source = "databricks/databricks"
    }
  }
}

provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

# COMMENT OUT THIS BLOCK for import!
provider "databricks" {
  azure_workspace_resource_id = azurerm_databricks_workspace.dbxWorkspace.id
  azure_client_id             = var.client_id
  azure_client_secret         = var.client_secret
  azure_tenant_id             = var.tenant_id
}
