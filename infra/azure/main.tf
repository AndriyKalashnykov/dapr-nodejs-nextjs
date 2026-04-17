terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.69.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # See create-tfstate-storage.sh for variable values
  backend "azurerm" {
    resource_group_name  = "terraformstate"
    storage_account_name = "tfstore008675309"
    container_name       = "tfstate"
    key                  = "staging.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.AZURE_SUBSCRIPTION_ID
}

data "azurerm_client_config" "current" {
}

resource "random_string" "resource_prefix" {
  length  = 6
  special = false
  upper   = false
  numeric = false
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.resource_group_name}"
  location = var.location
  tags     = var.tags
}

module "log_analytics_workspace" {
  source              = "./modules/log_analytics"
  name                = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.log_analytics_workspace_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

module "application_insights" {
  source              = "./modules/application_insights"
  name                = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.application_insights_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
  application_type    = var.application_insights_application_type
  workspace_id        = module.log_analytics_workspace.id
}

module "virtual_network" {
  source              = "./modules/virtual_network"
  resource_group_name = azurerm_resource_group.rg.name
  vnet_name           = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.vnet_name}"
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags

  subnets = [
    {
      name : var.aca_subnet_name
      address_prefixes : var.aca_subnet_address_prefix
      private_endpoint_network_policies : "Enabled"
      private_link_service_network_policies_enabled : false
    },
    {
      name : var.private_endpoint_subnet_name
      address_prefixes : var.private_endpoint_subnet_address_prefix
      private_endpoint_network_policies : "Enabled"
      private_link_service_network_policies_enabled : false
    }
  ]
}

module "blob_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "blob_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = "${title(module.storage_account.name)}PrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.virtual_network.subnet_ids[var.private_endpoint_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.storage_account.id
  is_manual_connection           = false
  subresource_name               = "blob"
  private_dns_zone_group_name    = "BlobPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.blob_private_dns_zone.id]
}

module "storage_account" {
  source              = "./modules/storage_account"
  name                = "${random_string.resource_prefix.result}${var.storage_account_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
  account_kind        = var.storage_account_kind
  account_tier        = var.storage_account_tier
  replication_type    = var.storage_account_replication_type
}

module "container_registry" {
  source              = "./modules/container_registry"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

module "redis_cache_backend" {
  source              = "./modules/redis_cache"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
  cache_name          = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}backendcache"
}

module "redis_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "redis_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = "${title(module.redis_cache_backend.name)}PrivateEndpoint"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  subnet_id                      = module.virtual_network.subnet_ids[var.private_endpoint_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.redis_cache_backend.id
  is_manual_connection           = false
  subresource_name               = "redisCache"
  private_dns_zone_group_name    = "RedisPrivateDnsZoneGroup"
  private_dns_zone_group_ids     = [module.redis_private_dns_zone.id]
}

# ── PostgreSQL ───────────────────────────────────────────────────────────────
# Flexible Server with VNet integration. Uses a dedicated delegated subnet
# (Postgres FS requires exclusive delegation) and a private DNS zone linked
# to the VNet so containers resolve the server's FQDN privately.

resource "azurerm_subnet" "postgres" {
  name                 = var.postgres_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = module.virtual_network.name
  address_prefixes     = var.postgres_subnet_address_prefix

  delegation {
    name = "fs"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

module "postgres_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.rg.name
    }
  }
}

module "postgres" {
  source              = "./modules/postgresql_flexible"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
  server_name         = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.postgres_server_name}"
  postgres_version    = var.postgres_version
  sku_name            = var.postgres_sku_name
  storage_mb          = var.postgres_storage_mb
  storage_tier        = var.postgres_storage_tier
  database_name       = var.postgres_database_name
  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = module.postgres_private_dns_zone.id
}

module "container_app_environment" {
  source                   = "./modules/container_app_environment"
  managed_environment_name = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.managed_environment_name}"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.rg.name
  tags                     = var.tags
  infrastructure_subnet_id = module.virtual_network.subnet_ids[var.aca_subnet_name]
  workspace_id             = module.log_analytics_workspace.id
}

# ── Key Vault + Dapr secretstore ─────────────────────────────────────────────
# Key Vault holds JWT secrets, DB creds, and the Redis password. Container
# Apps read them through Dapr's azure.keyvault secretstore using the
# container-app managed identity (role assignment happens in the container_app
# module; see Milestone 4 in docs/aca-deploy-test-plan.md).

module "key_vault" {
  source              = "./modules/key_vault"
  name                = "${var.resource_prefix != "" ? var.resource_prefix : random_string.resource_prefix.result}${var.key_vault_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  # Seed secrets read by Dapr at component init. Values come from the modules
  # that own them — never hardcoded here.
  secrets = {
    "jwt-secret-key"    = var.jwt_secret_key
    "postgres-password" = module.postgres.administrator_password
    "redis-password"    = module.redis_cache_backend.primary_access_key
  }
}

module "dapr_components" {
  source                 = "./modules/dapr_components"
  managed_environment_id = module.container_app_environment.managed_environment_id
  dapr_components = [
    #    {
    #      name            = var.dapr_state_name
    #      component_type  = var.dapr_state_component_type
    #      version         = var.dapr_version
    #      ignore_errors   = var.dapr_ignore_errors
    #      init_timeout    = var.dapr_init_timeout
    #      secret          = [
    #        {
    #          name        = "storageaccountkey"
    #          value       = module.storage_account.primary_access_key
    #        }
    #      ]
    #      metadata: [
    #        {
    #          name        = "accountName"
    #          value       = module.storage_account.name
    #        },
    #        {
    #          name        = "containerName"
    #          value       = var.container_name
    #        },
    #        {
    #          name        = "accountKey"
    #          secret_name = "storageaccountkey"
    #        }
    #      ]
    #      scopes          = var.dapr_scopes
    #    },
    {
      name           = var.dapr_state_name
      component_type = var.dapr_state_component_type
      version        = var.dapr_version
      ignore_errors  = var.dapr_ignore_errors
      init_timeout   = var.dapr_init_timeout
      metadata : [
        {
          name  = "redisHost"
          value = "${module.redis_cache_backend.name}.${module.redis_private_dns_zone.name}:6379"
        },
        {
          name  = "redisPassword"
          value = module.redis_cache_backend.primary_access_key
        }
      ]
      scopes = var.dapr_scopes
    },
    {
      name           = var.dapr_pubsub_name
      component_type = var.dapr_pubsub_component_type
      version        = var.dapr_version
      ignore_errors  = var.dapr_ignore_errors
      init_timeout   = var.dapr_init_timeout
      metadata : [
        {
          name  = "redisHost"
          value = "${module.redis_cache_backend.name}.${module.redis_private_dns_zone.name}:6379"
        },
        {
          name  = "redisPassword"
          value = module.redis_cache_backend.primary_access_key
        },
        {
          name  = "consumerID"
          value = "{appID}"
        },
        {
          name  = "maxLenApprox"
          value = 1000
        }
      ]
      scopes = var.dapr_scopes
    },
    # Secretstore: Dapr's azure.keyvault component. Container-app MI
    # (see module "container_app") needs the "Key Vault Secrets User" role on
    # the KV. The backend reads JWT/DB/Redis creds via Dapr secretstore
    # (see packages/@sos/sdk/src/secrets) — same code path as `local-secretstore`.
    {
      name           = var.dapr_secretstore_name
      component_type = "secretstores.azure.keyvault"
      version        = var.dapr_version
      ignore_errors  = false
      init_timeout   = var.dapr_init_timeout
      metadata : [
        {
          name  = "vaultName"
          value = module.key_vault.name
        },
      ]
      scopes = var.dapr_scopes
    }
  ]
}

# ── Container Apps ───────────────────────────────────────────────────────────
# Both apps run with the Dapr sidecar injected by ACA (container-app-scoped
# Dapr enabled via the `dapr {}` block). Images come from the ACR provisioned
# above; image tags are passed as vars so CI can pin them per build.

locals {
  # Backend reads DB_HOST/PORT/NAME etc. from env, and DB_USER/DB_PASSWORD
  # from Dapr secretstore (see packages/@sos/sdk/src/secrets). Non-secret
  # env vars are listed here; secrets are resolved via Dapr.
  backend_env = [
    { name = "SERVICE_NAME", value = var.backend_app_id },
    { name = "NODE_ENV", value = "production" },
    { name = "SERVER_HOST", value = "0.0.0.0" },
    { name = "SERVER_PORT", value = "3001" },
    { name = "DAPR_HOST", value = "localhost" },
    { name = "DAPR_PORT", value = "3500" },
    { name = "DB_HOST", value = module.postgres.fqdn },
    { name = "DB_PORT", value = "5432" },
    { name = "DB_NAME", value = module.postgres.database_name },
    { name = "DB_SCHEMA", value = "backend_ts" },
    { name = "DB_SSL", value = "postgres" },
    { name = "SECRETS_KEY", value = "serviceSecrets" },
    { name = "SECRETS_STORE_NAME", value = var.dapr_secretstore_name },
    { name = "LOG_LEVEL", value = var.log_level },
    # App Insights integration: apps read APPLICATIONINSIGHTS_CONNECTION_STRING
    # when using @azure/monitor-opentelemetry (prod-grade AI exporter). The
    # OTLP_ENDPOINT path used locally (→ grafana-otel collector) doesn't apply
    # in ACA. Follow-up: wire backend-ts instrumentation to use this var.
    { name = "APPLICATIONINSIGHTS_CONNECTION_STRING", secret_name = "app-insights-connection-string" },
  ]

  nextjs_env = [
    { name = "NODE_ENV", value = "production" },
    { name = "DAPR_HOST", value = "localhost" },
    { name = "DAPR_PORT", value = "3500" },
    { name = "BACKEND_APP_ID", value = var.backend_app_id },
    { name = "LOG_LEVEL", value = var.log_level },
    # JWT_SECRET_KEY backed by KV via the Container App secret mechanism.
    { name = "JWT_SECRET_KEY", secret_name = "jwt-secret-key" },
    { name = "APPLICATIONINSIGHTS_CONNECTION_STRING", secret_name = "app-insights-connection-string" },
  ]
}

module "backend_ts" {
  source                 = "./modules/container_app"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = var.location
  tags                   = var.tags
  managed_environment_id = module.container_app_environment.managed_environment_id
  container_registry_id  = module.container_registry.id

  container_app = {
    name          = var.backend_app_id
    revision_mode = "Single"

    registry = {
      server = module.container_registry.login_server
    }

    dapr = {
      app_id       = var.backend_app_id
      app_port     = 3001
      app_protocol = "http"
    }

    ingress = {
      external_enabled = true
      target_port      = 3001
      transport        = "auto"
      traffic_weight = [{
        latest_revision = true
        percentage      = 100
      }]
    }

    # JWT key materialized as a Container App secret from the KV-held value.
    # At runtime it's injected into the container as $JWT_SECRET_KEY via the
    # env mapping below.
    secrets = [
      { name = "jwt-secret-key", value = var.jwt_secret_key },
      { name = "app-insights-connection-string", value = module.application_insights.connection_string },
    ]

    template = {
      min_replicas = 1
      max_replicas = 2
      containers = [{
        name   = var.backend_app_id
        image  = "${module.container_registry.login_server}/${var.backend_app_id}:${var.backend_image_tag}"
        cpu    = 0.5
        memory = "1Gi"
        env = concat(
          [for e in local.backend_env : e],
          [{ name = "JWT_SECRET_KEY", secret_name = "jwt-secret-key" }],
        )
      }]
    }
  }
}

module "web_nextjs" {
  source                 = "./modules/container_app"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = var.location
  tags                   = var.tags
  managed_environment_id = module.container_app_environment.managed_environment_id
  container_registry_id  = module.container_registry.id

  container_app = {
    name          = var.nextjs_app_id
    revision_mode = "Single"

    registry = {
      server = module.container_registry.login_server
    }

    dapr = {
      app_id       = var.nextjs_app_id
      app_port     = 3000
      app_protocol = "http"
    }

    ingress = {
      external_enabled = true
      target_port      = 3000
      transport        = "auto"
      traffic_weight = [{
        latest_revision = true
        percentage      = 100
      }]
    }

    secrets = [
      { name = "jwt-secret-key", value = var.jwt_secret_key },
      { name = "app-insights-connection-string", value = module.application_insights.connection_string },
    ]

    template = {
      min_replicas = 1
      max_replicas = 2
      containers = [{
        name   = var.nextjs_app_id
        image  = "${module.container_registry.login_server}/${var.nextjs_app_id}:${var.nextjs_image_tag}"
        cpu    = 0.5
        memory = "1Gi"
        env    = local.nextjs_env
      }]
    }
  }
}

# ── Role assignments: container-app MIs → KV (Secrets User) ──────────────────
# Dapr's azure.keyvault secretstore uses the Container App's managed identity
# to authenticate against KV. Both apps need "Key Vault Secrets User" on the
# same vault so the shared secretstore component resolves for each.

resource "azurerm_role_assignment" "backend_kv_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.backend_ts.identity_principal_id
}

resource "azurerm_role_assignment" "nextjs_kv_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.web_nextjs.identity_principal_id
}

