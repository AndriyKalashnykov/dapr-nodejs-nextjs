terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.69.0"
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name
  tags                = var.tags

  # RBAC model (not legacy access policies) — Dapr MI needs "Key Vault Secrets User".
  rbac_authorization_enabled = true

  # No public access; containers reach KV via private endpoint.
  public_network_access_enabled = var.public_network_access_enabled
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days

  network_acls {
    bypass         = "AzureServices"
    default_action = var.default_action
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Grant the deployer (whoever runs `terraform apply`) rights to seed secrets.
resource "azurerm_role_assignment" "terraform_runner_secrets_officer" {
  count                = var.grant_terraform_runner_secrets_officer ? 1 : 0
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Seed initial secrets.
#
# `nonsensitive(toset(keys(...)))` lets Terraform iterate on secret names
# (safe to expose in resource addresses) while the values stay sensitive.
# Directly using `var.secrets` in `for_each` fails because the whole map is
# marked sensitive at the caller.
resource "azurerm_key_vault_secret" "secrets" {
  for_each     = nonsensitive(toset(keys(var.secrets)))
  name         = each.key
  value        = var.secrets[each.key]
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.terraform_runner_secrets_officer]
}
