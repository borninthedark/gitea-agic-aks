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
      "annotations" : {
        "kubernetes.io/ingress.class" : "azure/application-gateway"
      },
      "name" : "gitea-ingress",
      "namespace" : "gitea"
    },
    "spec" : {
      "ingressClassName" : "azure-application-gateway",
      "rules" : [
        {
          "http" : {
            "paths" : [
              {
                "pathType" : "Prefix",
                "path" : "/",
                "backend" : {
                  "service" : {
                    "name" : "gitea-http",
                    "port" : {
                      "number" : 80
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
