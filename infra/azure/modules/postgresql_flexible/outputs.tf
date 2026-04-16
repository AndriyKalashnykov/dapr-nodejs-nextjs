output "id" {
  value       = azurerm_postgresql_flexible_server.postgres.id
  description = "Resource ID of the PostgreSQL server."
}

output "name" {
  value       = azurerm_postgresql_flexible_server.postgres.name
  description = "Name of the PostgreSQL server."
}

output "fqdn" {
  value       = azurerm_postgresql_flexible_server.postgres.fqdn
  description = "FQDN of the server (e.g., mydemo-pg.postgres.database.azure.com)."
}

output "administrator_login" {
  value       = azurerm_postgresql_flexible_server.postgres.administrator_login
  description = "Admin username."
}

output "administrator_password" {
  value       = local.admin_password
  sensitive   = true
  description = "Admin password. Persist in Key Vault; never echo to logs."
}

output "database_name" {
  value       = azurerm_postgresql_flexible_server_database.app_db.name
  description = "Application database name."
}
