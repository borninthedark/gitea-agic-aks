resource "azurerm_resource_group" "aks" {
  name     = "${var.prefix}-aks-rg"
  location = var.location
}

###############################################################################

#Virtual Networks

resource "azurerm_virtual_network" "aks" {
  name                = "${var.prefix}-aks-vnet"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.aks.name
  address_prefixes     = ["10.0.1.0/24"]
  virtual_network_name = azurerm_virtual_network.aks.name
}

resource "azurerm_virtual_network" "appgw" {
  name                = "${var.prefix}-appgw-vnet"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  address_space       = ["10.254.0.0/16"]
}
resource "azurerm_subnet" "frontend" {
  name                 = "${var.prefix}-frontend"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.appgw.name
  address_prefixes     = ["10.254.0.0/24"]
}
resource "azurerm_subnet" "backend" {
  name                 = "${var.prefix}-backend"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.appgw.name
  address_prefixes     = ["10.254.2.0/24"]
}
resource "azurerm_public_ip" "frontend-publicIP" {
  name                = "${var.prefix}-pip"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  allocation_method   = "Static"
}

###########################################################################

# AppGw to AKS
resource "azurerm_virtual_network_peering" "appgw_aks_peering" {
  name                      = "${var.prefix}-appgw-aks-peer"
  resource_group_name       = data.azurerm_resource_group.aks.name
  virtual_network_name      = data.azurerm_virtual_network.appgw.id
  remote_virtual_network_id = data.azurerm_virtual_network.aks.id
}

# AKS to AppGw
resource "azurerm_virtual_network_peering" "aks_appgw_peering" {
  name                      = "${var.prefix}-aks-appgw-peer"
  resource_group_name       = data.azurerm_resource_group.aks.name
  virtual_network_name      = data.azurerm_virtual_network.aks.id
  remote_virtual_network_id = data.azurerm_virtual_network.appgw.id
}


#################################################################################

resource "azurerm_application_gateway" "network" {
  name                = "${var.prefix}-appgateway"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }
  gateway_ip_configuration {
    name      = "${var.prefix}-gateway-ip-configuration"
    subnet_id = azurerm_subnet.frontend.id
  }
  frontend_port {
    name = local.frontend_port_name
    port = 80
  }
  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.frontend-publicIP.id
  }
  backend_address_pool {
    name = local.backend_address_pool_name
  }
  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 3000
    protocol              = "Http"
    request_timeout       = var.dns_ttl
  }
  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}


#################################################################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                      = "${var.prefix}-aks-cluster"
  workload_identity_enabled = true
  kubernetes_version        = var.kubernetes_version
  location                  = var.location
  oidc_issuer_enabled       = true
  resource_group_name       = azurerm_resource_group.aks.name
  dns_prefix                = "${var.prefix}-aks-cluster"
  node_resource_group       = data.azurerm_resource_group.aks.name
  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.network.id
  }

  default_node_pool {
    name           = "system"
    node_count     = var.system_node_count
    vm_size        = "Standard_B2s"
    type           = "VirtualMachineScaleSets"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  linux_profile {
    admin_username = "${var.prefix}-admin"

    ssh_key {
      key_data = file(var.public_ssh_key_path)
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "${var.prefix}-Dev"
  }

  network_profile {
    load_balancer_sku = "standard"
    network_plugin    = "kubenet"
  }
}

# create namespace for cert mananger
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    labels = {
      "name" = "${var.prefix}-cert-manager"
    }
    name = "cert-manager"
  }
}

# Install cert-manager helm chart using terraform
resource "helm_release" "cert_manager" {
  name            = "cert-manager"
  repository      = "https://charts.jetstack.io"
  chart           = "cert-manager"
  force_update    = true
  version         = "v1.16.1"
  cleanup_on_fail = true
  namespace       = kubernetes_namespace.cert_manager.metadata.0.name

  values = [
    "${file("certmgr-deploy/values.yml")}"
  ]

  set {
    name  = "installCRDs"
    value = "true"
  }
  depends_on = [
    kubernetes_namespace.cert_manager
  ]
}

# create namespace for gitea
resource "kubernetes_namespace" "gitea" {
  metadata {
    labels = {
      "name" = "${var.prefix}-gitea"
    }
    name = "gitea"
  }
}

# Install gitea helm chart using terraform
resource "helm_release" "gitea" {
  name          = "gitea"
  repository    = "https://dl.gitea.com/charts/"
  chart         = "gitea"
  force_update  = true
  recreate_pods = true
  namespace     = kubernetes_namespace.gitea.metadata.0.name
  values = [
    "${file("gitea-deploy/values.yml")}"
  ]

  set {
    name  = "installCRDs"
    value = "true"
  }
  depends_on = [
    kubernetes_namespace.gitea
  ]
}


########################################################################################

resource "azurerm_user_assigned_identity" "user_identity" {
  location            = azurerm_resource_group.aks.location
  name                = "${var.prefix}-identity"
  resource_group_name = azurerm_resource_group.aks.name
}

resource "azurerm_federated_identity_credential" "workload_identity" {
  name                = azurerm_user_assigned_identity.user_identity.name
  resource_group_name = azurerm_user_assigned_identity.user_identity.resource_group_name
  parent_id           = azurerm_user_assigned_identity.user_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "gitea"
}

resource "azurerm_role_assignment" "role_assignment" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = "${data.azurerm_subscription.current.id}${data.azurerm_role_definition.contributor.id}"
  principal_id       = azurerm_user_assigned_identity.user_identity.principal_id
}

resource "azurerm_role_assignment" "managed_id_ra" {
  scope                = azurerm_resource_group.aks.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.user_identity.principal_id
  lifecycle {
    ignore_changes = [
      skip_service_principal_aad_check,
    ]
  }
}

resource "azurerm_role_assignment" "dns_contributor" {
  scope                = azurerm_dns_zone.zone.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.user_identity.principal_id
}

# Give the APPGW identity Network Contributor access to the AKS cluster resource group for a peering.   
resource "azurerm_role_assignment" "identity_aks_netcontributor_ra" {
  scope                = azurerm_resource_group.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azurerm_user_assigned_identity.pod_identity_appgw.principal_id
  # skip_service_principal_aad_check = true
  lifecycle {
    ignore_changes = [
      skip_service_principal_aad_check,
    ]
  }
  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

# Give the AKS identity Network Contributor access to the APPGW resource group for a peering.   
resource "azurerm_role_assignment" "identity_aks_appgtw_netcontributor_ra" {
  scope                = data.azurerm_application_gateway.network.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azurerm_user_assigned_identity.user_identity.principal_id
  # skip_service_principal_aad_check = true
  lifecycle {
    ignore_changes = [
      skip_service_principal_aad_check,
    ]
  }
  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

###################################################################################

resource "azurerm_dns_zone" "zone" {
  name = (
    var.dns_zone_name
  )
  resource_group_name = azurerm_resource_group.aks.name
}

resource "azurerm_dns_a_record" "alias" {
  name                = "@"
  zone_name           = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.aks.name
  ttl                 = var.dns_ttl
  target_resource_id  = data.azurerm_public_ip.publicIP.id
}

resource "azurerm_dns_cname_record" "gitea" {
  name                = "gitea"
  zone_name           = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.aks.name
  ttl                 = var.dns_ttl
  record              = var.dns_zone_name
}