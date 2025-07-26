variable "client_id" {
  description = "Azure Service Principal Client ID"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure Tenant ID"
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}
