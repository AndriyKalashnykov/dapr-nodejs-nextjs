terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.70.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_password" "admin_password" {
  count   = var.administrator_password == null ? 1 : 0
  length  = 24
  special = true
  # Azure PostgreSQL disallows these in passwords
  override_special = "!@#$%^&*()-_=+[]{}:?"
}

locals {
  admin_password = var.administrator_password != null ? var.administrator_password : random_password.admin_password[0].result
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                          = var.server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.postgres_version
  sku_name                      = var.sku_name
  storage_mb                    = var.storage_mb
  storage_tier                  = var.storage_tier
  backup_retention_days         = var.backup_retention_days
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = false

  administrator_login    = var.administrator_login
  administrator_password = local.admin_password

  # Private DNS integration for the delegated subnet (ACA pattern)
  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  authentication {
    password_auth_enabled = true
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      tags,
      # Azure requires zone to be sticky once HA is enabled; leave managed.
      zone,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "app_db" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = false
  }
}
