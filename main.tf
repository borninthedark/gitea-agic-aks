resource "azurerm_resource_group" "aks" {
  name     = "${var.prefix}-rg"
  location = var.location
}

#############################################################################
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
}

resource "azurerm_subnet" "default_sn" {
  name                 = "${var.prefix}-sn"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.10.0/24"]
}

resource "azurerm_subnet" "aks_sn" {
  name                 = "${var.prefix}-aks-sn"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.20.0/24"]
}

resource "azurerm_public_ip" "appgw_public_ip" {
  name                = "${var.prefix}-appgw-public-ip"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

#################################################################################

resource "azurerm_application_gateway" "appgw" {
  name                = "${var.prefix}-appgw"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-configuration"
    subnet_id = azurerm_subnet.default_sn.id
  }

  frontend_ip_configuration {
    name                 = "appgw-front-end-ip"
    public_ip_address_id = azurerm_public_ip.appgw_public_ip.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  backend_address_pool {
    name = "appgw-backend-pool"
  }

  backend_http_settings {
    name                  = "appgw-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 3000
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "appgw-listener"
    frontend_ip_configuration_name = "appgw-front-end-ip"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "appgw-rule"
    rule_type                  = "Basic"
    http_listener_name         = "appgw-listener"
    backend_address_pool_name  = "appgw-backend-pool"
    backend_http_settings_name = "appgw-http-settings"
    priority                   = 100 # Added priority
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
  # node_resource_group       = "MC_${data.azurerm_resource_group.rg.name}_${azurerm_kubernetes_cluster.aks.name}_${var.aks_rg_suffix}"
  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.appgw.id
  }

  default_node_pool {
    name           = "system"
    node_count     = var.system_node_count
    vm_size        = "Standard_B2s"
    type           = "VirtualMachineScaleSets"
    vnet_subnet_id = azurerm_subnet.aks_sn.id
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
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    service_cidr      = "10.10.40.0/24"
    dns_service_ip    = "10.10.40.10" # Added to match service_cidr
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
  scope                = azurerm_application_gateway.appgw.id
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
  target_resource_id  = azurerm_public_ip.appgw_public_ip.id
}

resource "azurerm_dns_cname_record" "gitea" {
  name                = "gitea"
  zone_name           = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.aks.name
  ttl                 = var.dns_ttl
  record              = var.dns_zone_name
}