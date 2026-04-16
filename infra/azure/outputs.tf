# These output values are used in *.tfvars files for individual microservices infra, see app/*/infra/azure/*.tfvars files

output "container_registry_host" {
  value = module.container_registry.login_server
}

output "container_registry_id" {
  value = module.container_registry.id
}

output "resource_group_name" {
  value = resource.azurerm_resource_group.rg.name
}

output "managed_environment_id" {
  value = module.container_app_environment.managed_environment_id
}

output "location" {
  value = var.location
}

output "tags" {
  value = var.tags
}

output "postgres_fqdn" {
  value       = module.postgres.fqdn
  description = "Postgres Flexible Server FQDN. Use as DB_HOST for apps in the ACA env."
}

output "postgres_database_name" {
  value = module.postgres.database_name
}

output "postgres_admin_login" {
  value = module.postgres.administrator_login
}

output "postgres_admin_password" {
  value       = module.postgres.administrator_password
  sensitive   = true
  description = "Generated admin password (if not supplied). Push to Key Vault, never echo."
}

output "key_vault_id" {
  value       = module.key_vault.id
  description = "Key Vault resource ID. Used to grant container-app MI `Key Vault Secrets User`."
}

output "key_vault_name" {
  value       = module.key_vault.name
  description = "Key Vault name. Referenced by the Dapr secretstore component `vaultName` metadata."
}

output "key_vault_uri" {
  value       = module.key_vault.vault_uri
  description = "Key Vault URI (https://...). For direct SDK access if not using Dapr."
}

output "backend_fqdn" {
  value       = module.backend_ts.container_app_fqdn
  description = "Public FQDN of backend-ts. Use for direct HTTP smoke tests."
}

output "backend_url" {
  value       = module.backend_ts.container_app_fqdn == null ? null : "https://${module.backend_ts.container_app_fqdn}"
  description = "Full HTTPS URL of backend-ts ingress."
}

output "nextjs_fqdn" {
  value       = module.web_nextjs.container_app_fqdn
  description = "Public FQDN of web-nextjs. Use for browser / Playwright smoke tests."
}

output "nextjs_url" {
  value       = module.web_nextjs.container_app_fqdn == null ? null : "https://${module.web_nextjs.container_app_fqdn}"
  description = "Full HTTPS URL of the Next.js SSR frontend."
}

output "container_registry_login_server" {
  value       = module.container_registry.login_server
  description = "ACR login server. CI tags images as <login_server>/<app>:<git_sha> and pushes before `terraform apply`."
}
