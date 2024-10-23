output "client_certificate" {
  value     = azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.aks.kube_config_raw

  sensitive = true
}

output "aks_id" {
  value = azurerm_kubernetes_cluster.aks.id
}

output "aks_fqdn" {
  value = azurerm_kubernetes_cluster.aks.fqdn
}

output "aks_node_rg" {
  value = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "myworkload_identity_client_id" {
  description = "The client ID of the created managed identity to use for the annotation 'azure.workload.identity/client-id' on your service account"
  value       = azurerm_user_assigned_identity.user_identity.client_id
}

output "current_subscription_display_name" {
  value = data.azurerm_subscription.current.display_name
}

output "dns_zone_name" {
  value = data.azurerm_dns_zone.zone.name
}

output "dns_zone_id" {
  value = data.azurerm_dns_zone.zone.id
}

output "name_servers" {
  value = azurerm_dns_zone.zone.name_servers
}

output "uai_client_id" {
  value = data.azurerm_user_assigned_identity.user_identity.client_id
}
