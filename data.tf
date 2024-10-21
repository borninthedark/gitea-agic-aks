data "azurerm_user_assigned_identity" "pod_identity_appgw" {
  name                = "httpapplicationrouting-${azurerm_kubernetes_cluster.aks.name}"
  resource_group_name = var.node_resource_group
  depends_on = [
    data.azurerm_resource_group.appgtw_rg,
    azurerm_kubernetes_cluster.aks,
  ]
}

data "azurerm_user_assigned_identity" "user_identity" {
  name                = azurerm_user_assigned_identity.user_identity.name
  resource_group_name = azurerm_resource_group.rg.name
}

data "azurerm_public_ip" "publicIP" {
  name                = reverse(split("/", tolist(azurerm_kubernetes_cluster.aks.network_profile.0.load_balancer_profile.0.effective_outbound_ips)[0]))[0]
  resource_group_name = var.node_resource_group
}

data "azurerm_role_definition" "contributor" {
  name = "Contributor"
}

data "azurerm_subscription" "current" {
}

data "azurerm_resource_group" "appgtw_rg" {
  name = var.node_resource_group
  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

# Create gitea ingress file
data "kubectl_file_documents" "gitea_ingress" {
  content = file(local.gitea_ingress)
}

data "azurerm_dns_zone" "zone" {
  name                = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.rg.name
}

data "azurerm_virtual_network" "vnet" {
  name                = azurerm_virtual_network.vnet.name
  resource_group_name = azurerm_resource_group.rg.name
}


