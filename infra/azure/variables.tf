variable "AZURE_SUBSCRIPTION_ID" {
  description = "Azure subscription ID. Supply via env TF_VAR_AZURE_SUBSCRIPTION_ID."
  type        = string
}

variable "resource_prefix" {
  description = "Specifies a prefix for all the resource names."
  type        = string
  default     = "demots"
}

variable "location" {
  description = "(Required) Specifies the supported Azure location where the resource exists. Changing this forces a new resource to be created."
  type        = string
  default     = "WestUS2"
}

variable "resource_group_name" {
  description = "Name of the resource group in which the resources will be created"
  type        = string
  default     = "RG"
}

variable "tags" {
  description = "(Optional) Specifies tags for all the resources"
  type        = map(string)
  default = {
    createdBy = "infrastructure"
  }
}

variable "log_analytics_workspace_name" {
  description = "Specifies the name of the log analytics workspace"
  default     = "Workspace"
  type        = string
}

variable "application_insights_name" {
  description = "Specifies the name of the application insights resource."
  default     = "ApplicationInsights"
  type        = string
}

variable "application_insights_application_type" {
  description = "(Required) Specifies the type of Application Insights to create. Valid values are ios for iOS, java for Java web, MobileCenter for App Center, Node.JS for Node.js, other for General, phone for Windows Phone, store for Windows Store and web for ASP.NET. Please note these values are case sensitive; unmatched values are treated as ASP.NET by Azure. Changing this forces a new resource to be created."
  type        = string
  default     = "web"
}

variable "vnet_name" {
  description = "Specifies the name of the virtual network"
  default     = "VNet"
  type        = string
}

variable "vnet_address_space" {
  description = "Specifies the address prefix of the virtual network"
  default     = ["10.0.0.0/16"]
  type        = list(string)
}

variable "aca_subnet_name" {
  description = "Specifies the name of the subnet"
  default     = "ContainerApps"
  type        = string
}

variable "aca_subnet_address_prefix" {
  description = "Specifies the address prefix of the Azure Container Apps environment subnet"
  default     = ["10.0.0.0/20"]
  type        = list(string)
}

variable "private_endpoint_subnet_name" {
  description = "Specifies the name of the subnet"
  default     = "PrivateEndpoints"
  type        = string
}

variable "private_endpoint_subnet_address_prefix" {
  description = "Specifies the address prefix of the private endpoints subnet"
  default     = ["10.0.16.0/24"]
  type        = list(string)
}

variable "storage_account_name" {
  description = "(Optional) Specifies the name of the storage account"
  default     = "account"
  type        = string
}

variable "storage_account_replication_type" {
  description = "(Optional) Specifies the replication type of the storage account"
  default     = "LRS"
  type        = string

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RA-GRS", "RA-GZRS"], var.storage_account_replication_type)
    error_message = "The replication type of the storage account is invalid."
  }
}

variable "storage_account_kind" {
  description = "(Optional) Specifies the account kind of the storage account"
  default     = "StorageV2"
  type        = string

  validation {
    condition     = contains(["Storage", "StorageV2"], var.storage_account_kind)
    error_message = "The account kind of the storage account is invalid."
  }
}

variable "storage_account_tier" {
  description = "(Optional) Specifies the account tier of the storage account"
  default     = "Standard"
  type        = string

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "The account tier of the storage account is invalid."
  }
}

variable "managed_environment_name" {
  description = "(Required) Specifies the name of the managed environment."
  type        = string
  default     = "ManagedEnvironment"
}

#{# PostgreSQL variables #}
variable "postgres_subnet_name" {
  description = "Name of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
  default     = "Postgres"
}

variable "postgres_subnet_address_prefix" {
  description = "Address prefix for the Postgres delegated subnet."
  type        = list(string)
  default     = ["10.0.17.0/24"]
}

variable "postgres_server_name" {
  description = "Suffix for the PostgreSQL Flexible Server name. Prefixed with resource_prefix for global uniqueness."
  type        = string
  default     = "pg"
}

variable "postgres_version" {
  description = "PostgreSQL major version. Azure Flexible Server supports up to 17; local dev runs 18."
  type        = string
  default     = "17"
}

variable "postgres_sku_name" {
  description = "Postgres Flexible Server SKU. Burstable is cheapest; memory/general-purpose tiers for prod."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  description = "Postgres storage allocation in MB (minimum 32768)."
  type        = number
  default     = 32768
}

variable "postgres_storage_tier" {
  description = "Postgres storage tier. P4 pairs with 32 GB."
  type        = string
  default     = "P4"
}

variable "postgres_database_name" {
  description = "Initial database name created on the server."
  type        = string
  default     = "postgres"
}

#{# Container Apps #}
variable "backend_app_id" {
  description = "Dapr app-id and Container App name for the backend. Used by web-nextjs in BACKEND_APP_ID env var; must match code in app/web-nextjs/src/services/backend-ts.ts."
  type        = string
  default     = "backend-ts"
}

variable "nextjs_app_id" {
  description = "Dapr app-id and Container App name for the Next.js SSR frontend."
  type        = string
  default     = "web-nextjs"
}

variable "backend_image_tag" {
  description = "Image tag for backend-ts. CI overrides with the git SHA of the build."
  type        = string
  default     = "latest"
}

variable "nextjs_image_tag" {
  description = "Image tag for web-nextjs. CI overrides with the git SHA of the build."
  type        = string
  default     = "latest"
}

variable "log_level" {
  description = "Pino log level for containers."
  type        = string
  default     = "info"
}

#{# Key Vault #}
variable "key_vault_name" {
  description = "Suffix for the Key Vault name. Prefixed with resource_prefix. Must end globally unique, 3–24 chars."
  type        = string
  default     = "kv"
}

variable "jwt_secret_key" {
  description = "JWT signing key used by backend-ts. Seeded into Key Vault; apps read via Dapr secretstore. Supply via TF_VAR_jwt_secret_key or tfvars — never default to a real secret."
  type        = string
  sensitive   = true
  default     = "change-me-at-apply-time"
}

#{# Dapr variables #}
# App-ids MUST match `--app-id` flags on the `daprd` sidecars (see
# app/*/docker-compose.yaml) and the Container App names (see module
# "container_app"). `dapr_scopes` below gates component access per app-id.

variable "dapr_state_name" {
  description = "Dapr state component name. Must match packages/@sos/sdk/src/state/index.ts `StateNames.REDIS`."
  type        = string
  default     = "redis-state"
}

variable "dapr_state_component_type" {
  description = "(Required) Specifies the type of the dapr component."
  type        = string
  default     = "state.redis"
}

variable "dapr_pubsub_name" {
  description = "Dapr pubsub component name. Must match packages/@sos/sdk/src/pubsub/index.ts `PubSubNames.REDIS`."
  type        = string
  default     = "redis-pubsub"
}

variable "dapr_pubsub_component_type" {
  description = "(Required) Specifies the type of the dapr component."
  type        = string
  default     = "pubsub.redis"
}

variable "dapr_secretstore_name" {
  description = "Dapr secretstore component name. Backend SDK reads via Secrets module (local-secretstore locally, this in prod)."
  type        = string
  default     = "azure-keyvault-secretstore"
}

variable "dapr_ignore_errors" {
  description = "(Required) Specifies if the component errors are ignored."
  type        = bool
  default     = false
}

variable "dapr_version" {
  description = "(Required) Specifies the version of the dapr component."
  type        = string
  default     = "v1"
}

variable "dapr_init_timeout" {
  description = "(Required) Specifies the init timeout of the dapr component."
  type        = string
  default     = "5s"
}

variable "dapr_scopes" {
  description = "Dapr component scope list. Defaults to every app-id in var.dapr_app_ids."
  type        = list(string)
  default     = ["backend-ts", "web-nextjs"]
}
