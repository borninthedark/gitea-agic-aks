resource "kubernetes_manifest" "clusterissuer_letsencrypt_staging" {
  depends_on = [
    helm_release.cert_manager
  ]
  manifest = {
    "apiVersion" : "cert-manager.io/v1",
    "kind" : "ClusterIssuer",
    "metadata" : {
      "name" : "letsencrypt-staging",
      "annotations" : {
        "cert-manager.io/cluster-issuer" : "letsencrypt-staging"
      }
    },
    "spec" : {
      "acme" : {
        "server" : "https://acme-staging-v02.api.letsencrypt.org/directory",
        "email" : "princeton.strong@outlook.com",
        "privateKeySecretRef" : {
          "name" : "letsencrypt-staging"
        },
        "solvers" : [
          {
            "dns01" : {
              "azureDNS" : {
                "hostedZoneName" : azurerm_dns_zone.zone.name
                "resourceGroupName" : azurerm_resource_group.rg.name,
                "subscriptionID" : data.azurerm_subscription.current.id
                "environment" : var.environment,
                "managedIdentity" : {
                  "clientID" : data.azurerm_user_assigned_identity.user_identity.client_id
                }
              }
            }
          }
        ]
      }
    }
  }
}

