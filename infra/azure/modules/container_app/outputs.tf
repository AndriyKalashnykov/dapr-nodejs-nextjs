output "container_app_fqdn" {
  value       = length(resource.azurerm_container_app.container_app.ingress) > 0 ? resource.azurerm_container_app.container_app.ingress[0].fqdn : null
  description = "Public FQDN of the container app's ingress. Null when ingress is disabled."
}

output "container_app_id" {
  value       = azurerm_container_app.container_app.id
  description = "Resource ID of the container app."
}

output "container_app_name" {
  value       = azurerm_container_app.container_app.name
  description = "Name of the container app (matches Dapr app-id when Dapr is enabled)."
}

output "identity_id" {
  value       = azurerm_user_assigned_identity.containerapp_identity.id
  description = "Resource ID of the container app's user-assigned managed identity."
}

output "identity_principal_id" {
  value       = azurerm_user_assigned_identity.containerapp_identity.principal_id
  description = "Principal (object) ID of the managed identity. Use for role assignments on Key Vault, Postgres, etc."
}
