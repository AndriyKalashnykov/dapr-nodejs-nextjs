variable "name" {
  description = "(Required) Key Vault name. Must be 3–24 chars, globally unique, alphanumeric + hyphen."
  type        = string
}

variable "location" {
  description = "(Required) Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Resource group name."
  type        = string
}

variable "tags" {
  description = "(Optional) Resource tags."
  type        = map(any)
  default     = {}
}

variable "sku_name" {
  description = "SKU: 'standard' (default) or 'premium' (HSM-backed keys)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be 'standard' or 'premium'."
  }
}

variable "public_network_access_enabled" {
  description = "If false, KV is only reachable via private endpoint. Set to true only for debugging."
  type        = bool
  default     = true
  # NOTE: default true so `terraform apply` from a developer laptop can seed
  # secrets. In steady-state prod, flip to false after the initial seed or
  # front KV with a private endpoint and set false from the start.
}

variable "purge_protection_enabled" {
  description = "If true, deleted vaults cannot be purged for the retention period. Lean false for dev/test."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Soft-delete retention in days (7–90)."
  type        = number
  default     = 7
}

variable "default_action" {
  description = "Network ACL default action when public access is enabled. 'Deny' + 'AzureServices' bypass is the prod-ready default."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.default_action)
    error_message = "default_action must be 'Allow' or 'Deny'."
  }
}

variable "grant_terraform_runner_secrets_officer" {
  description = "Grant the running service principal/user 'Key Vault Secrets Officer' so `azurerm_key_vault_secret` resources can seed. Disable if out-of-band seeding is preferred."
  type        = bool
  default     = true
}

variable "secrets" {
  description = "Map of secret name → value to seed. Values are sensitive; pass via tfvars, never echo."
  type        = map(string)
  sensitive   = true
  default     = {}
}
