# since these variables are re-used - a locals block makes this more maintainable
locals {
  gitea_ingress                  = "ingress/ingress.yml"
  clusterissuer                  = "certmgr-deploy/ci-nginx.yml"
  backend_address_pool_name      = "${azurerm_virtual_network.aks.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.aks.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.aks.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.aks.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.aks.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.aks.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.aks.name}-rdrcfg"
}

variable "location" {
  type        = string
  description = "Resources location in Microsoft Azure"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
}

variable "public_ssh_key_path" {
  description = "Public key path for SSH."
  type        = string
}

variable "system_node_count" {
  type        = number
  description = "Number of AKS worker nodes"
}

variable "prefix" {
  description = "A prefix used for all resources."
}

variable "workload_sa_name" {
  type        = string
  description = "Kubernetes service account to permit"
}

variable "workload_sa_namespace" {
  type        = string
  description = "Kubernetes service account namespace to permit"
}

variable "dns_zone_name" {
  type        = string
  default     = null
  description = "Name of the DNS zone."
}

variable "dns_ttl" {
  type        = number
  description = "Time To Live (TTL) of the DNS record (in seconds)."
}

variable "subscriptionID" {
  type        = string
  description = "The subscriptionID of the resources."
}

variable "environment" {
  type        = string
  description = "The environment of the resources."
}

variable "aks_rg_suffix" {
  type        = string
  description = "The environment of the resources."
}

