# Apply gitea ingress file
resource "kubernetes_manifest" "gitea_ingress" {
  depends_on = [
    helm_release.gitea,
    kubernetes_manifest.clusterissuer_letsencrypt_staging
  ]
  manifest = {
    "apiVersion" : "networking.k8s.io/v1",
    "kind" : "Ingress",
    "metadata" : {
      "name" : "gitea-ingress",
      "namespace" : "gitea",
      "annotations" : {
        "kubernetes.io/ingress.class" : "azure/application-gateway"
        "cert-manager.io/cluster-issuer" : "letsencrypt-staging",
        "appgw.ingress.kubernetes.io/ssl-redirect" : "true",
        "cert-manager.io/acme-challenge-type" : "dns01"
      }
    },
    "spec" : {
      "tls" : [
        {
          "hosts" : [
            "gitea.skypirate.cloud",
            "skypirate.cloud"
          ],
          "secretName" : "gitea-tls-secret",
        }
      ],
      "rules" : [
        {
          "host" : "gitea.skypirate.cloud",
          "http" : {
            "paths" : [
              {
                "path" : "/",
                "pathType" : "Prefix",
                "backend" : {
                  "service" : {
                    "name" : "gitea-http",
                    "port" : {
                      "number" : 3000
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}

