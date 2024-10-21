resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

###############################################################################

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["192.168.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["192.168.1.0/24"]
  virtual_network_name = azurerm_virtual_network.vnet.name
}

#################################################################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                             = "${var.prefix}-cluster"
  workload_identity_enabled        = true
  kubernetes_version               = var.kubernetes_version
  location                         = var.location
  http_application_routing_enabled = true
  oidc_issuer_enabled              = true
  resource_group_name              = azurerm_resource_group.rg.name
  dns_prefix                       = "${var.prefix}-cluster"
  node_resource_group              = var.node_resource_group

  default_node_pool {
    name       = "system"
    node_count = var.system_node_count
    vm_size    = "Standard_B2s"
    type       = "VirtualMachineScaleSets"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Dev"
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
  location            = azurerm_resource_group.rg.location
  name                = "${var.prefix}-identity"
  resource_group_name = azurerm_resource_group.rg.name
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

resource "azurerm_role_assignment" "dns_contributor" {
  scope                = azurerm_dns_zone.zone.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.user_identity.principal_id
}

resource "azurerm_role_assignment" "identity_appgw_contributor_ra" {
  scope                = data.azurerm_resource_group.appgtw_rg.id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_user_assigned_identity.pod_identity_appgw.principal_id
  # skip_service_principal_aad_check = true
  lifecycle {
    ignore_changes = [
      skip_service_principal_aad_check,
    ]
  }
  depends_on = [
    azurerm_kubernetes_cluster.aks,
  ]
}



# Give the identity Network Contributor access to the aks cluster resource group for a peering.   
resource "azurerm_role_assignment" "identity_aks_netcontributor_ra" {
  scope                = data.azurerm_virtual_network.vnet.id
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



###################################################################################

resource "azurerm_dns_zone" "zone" {
  name = (
    var.dns_zone_name
  )
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_dns_a_record" "alias" {
  name                = "@"
  zone_name           = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = var.dns_ttl
  target_resource_id  = data.azurerm_public_ip.publicIP.id
}

resource "azurerm_dns_cname_record" "gitea" {
  name                = "gitea"
  zone_name           = azurerm_dns_zone.zone.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = var.dns_ttl
  record              = var.dns_zone_name
}