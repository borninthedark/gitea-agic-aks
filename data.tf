data "azurerm_subscription" "current" {
}

data "azurerm_resource_group" "aks" {
  name = azurerm_resource_group.aks.name
}

data "azurerm_user_assigned_identity" "pod_identity_appgw" {
  name                = "ingressapplicationgateway-${azurerm_kubernetes_cluster.aks.name}"
  resource_group_name = azurerm_resource_group.aks.name
  depends_on = [
    azurerm_resource_group.aks,
    azurerm_kubernetes_cluster.aks,
  ]
}
data "azurerm_user_assigned_identity" "user_identity" {
  name                = azurerm_user_assigned_identity.user_identity.name
  resource_group_name = azurerm_resource_group.aks.name
}

data "azurerm_role_definition" "contributor" {
  name = "Contributor"
}

data "azurerm_virtual_network" "aks" {
  name                = azurerm_virtual_network.aks.name
  resource_group_name = azurerm_resource_group.aks.name
}

data "azurerm_virtual_network" "appgw" {
  name                = azurerm_virtual_network.appgw.name
  resource_group_name = azurerm_resource_group.aks.name
}

data "azurerm_subnet" "aks-subnet" {
  name                 = azurerm_subnet.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  resource_group_name  = data.azurerm_resource_group.aks.name
}

data "azurerm_subnet" "appgw-subnet" {
  name                 = azurerm_subnet.frontend.name
  virtual_network_name = azurerm_virtual_network.appgw.name
  resource_group_name  = data.azurerm_resource_group.aks.name
}

data "azurerm_public_ip" "publicIP" {
  name                = reverse(split("/", tolist(azurerm_kubernetes_cluster.aks.network_profile.0.load_balancer_profile.0.effective_outbound_ips)[0]))[0]
  resource_group_name = azurerm_resource_group.aks.name
}

data "azurerm_dns_zone" "zone" {
  name                = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.aks.name
}

data "azurerm_application_gateway" "network" {
  name                = azurerm_application_gateway.network.name
  resource_group_name = azurerm_resource_group.aks.name
}


