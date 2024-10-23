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

data "azurerm_dns_zone" "zone" {
  name                = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.aks.name
}


