variable "resource_group_name" {
  description = "(Required) Name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Azure region."
  type        = string
}

variable "tags" {
  description = "(Optional) Resource tags."
  type        = map(any)
  default     = {}
}

variable "server_name" {
  description = "(Required) Name of the PostgreSQL Flexible Server. Must be globally unique."
  type        = string
}

variable "postgres_version" {
  description = "PostgreSQL major version. Azure Flexible Server supports PG 18 GA since 2025-12-01; matches local dev."
  type        = string
  default     = "18"
}

variable "sku_name" {
  description = "SKU name. Burstable B1ms is the cheapest for dev/test (~$12/mo if long-running; destroyed per-run in e2e)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage allocation in MB. 32 GB is the minimum."
  type        = number
  default     = 32768
}

variable "storage_tier" {
  description = "Storage tier. P4 pairs with 32 GB."
  type        = string
  default     = "P4"
}

variable "backup_retention_days" {
  description = "Backup retention in days. 7 is the Azure minimum."
  type        = number
  default     = 7
}

variable "administrator_login" {
  description = "Admin login (must not be a reserved word like 'postgres' or 'admin')."
  type        = string
  default     = "dbadmin"
}

variable "administrator_password" {
  description = "Admin password. If null, a random password is generated and exposed via the `administrator_password` output (sensitive)."
  type        = string
  sensitive   = true
  default     = null
}

variable "database_name" {
  description = "Initial application database created on the server."
  type        = string
  default     = "postgres"
}

variable "delegated_subnet_id" {
  description = "ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. Required for VNet integration."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of the `privatelink.postgres.database.azure.com` private DNS zone, linked to the VNet."
  type        = string
}
