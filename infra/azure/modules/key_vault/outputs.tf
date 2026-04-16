output "id" {
  value       = azurerm_key_vault.kv.id
  description = "Resource ID of the Key Vault."
}

output "name" {
  value       = azurerm_key_vault.kv.name
  description = "Key Vault name."
}

output "vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "Vault URI (e.g., https://mykv.vault.azure.net/) — use for Dapr secretstore component."
}
