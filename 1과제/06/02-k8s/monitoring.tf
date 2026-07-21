resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  data = {
    "fluent-bit.conf" = templatefile("${path.module}/manifests/fluent-bit.conf.tftpl", {
      region = var.aws_region
    })
    "parsers.conf" = file("${path.module}/manifests/parsers.conf")
  }
}

resource "kubernetes_daemonset" "fluent_bit" {
  metadata {
    name      = "aws-for-fluent-bit"
    namespace = kubernetes_namespace.logging.metadata[0].name
    labels    = { app = "aws-for-fluent-bit" }
  }

  spec {
    selector {
      match_labels = { app = "aws-for-fluent-bit" }
    }

    template {
      metadata {
        labels = { app = "aws-for-fluent-bit" }
      }

      spec {
        service_account_name = kubernetes_service_account.fluent_bit.metadata[0].name

        container {
          name  = "aws-for-fluent-bit"
          image = "${local.ecr_public_mirror}/aws-observability/aws-for-fluent-bit:amd64-2.34.3.20260423"

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/fluent-bit.conf"
            sub_path   = "fluent-bit.conf"
          }

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/parsers.conf"
            sub_path   = "parsers.conf"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "image.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }

  set {
    name  = "image.repository"
    value = "grafana"
  }

  set {
    name  = "image.tag"
    value = "11.4.0"
  }

  set {
    name  = "downloadDashboardsImage.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }

  set {
    name  = "downloadDashboardsImage.repository"
    value = "curlimages/curl"
  }

  set {
    name  = "downloadDashboardsImage.tag"
    value = "8.9.1"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.grafana.metadata[0].name
  }

  set {
    name  = "adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "service.type"
    value = "ClusterIP"
  }

  set {
    name  = "service.port"
    value = "3000"
  }

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name  = "nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "gj2026-eks-addon-nodegroup"
  }

  values = [
    yamlencode({
      "grafana.ini" = {
        server = {
          root_url            = "%(protocol)s://%(domain)s/grafana"
          serve_from_sub_path = true
        }
      }
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "CloudWatch"
              uid       = "CloudWatch"
              type      = "cloudwatch"
              access    = "proxy"
              isDefault = true
              jsonData = {
                authType      = "default"
                defaultRegion = var.aws_region
              }
            },
          ]
        }
      }
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options         = { path = "/var/lib/grafana/dashboards/default" }
            },
          ]
        }
      }
      dashboards = {
        default = {
          wsi-dashboard = {
            json = jsonencode({
              title = "WSI Dashboard"
              uid   = "wsi-dashboard"
              time  = { from = "now-1h", to = "now" }
              panels = [
                {
                  id      = 1
                  title   = "Query Count Panel"
                  type    = "timeseries"
                  gridPos = { h = 8, w = 24, x = 0, y = 0 }
                  datasource = { type = "cloudwatch", uid = "CloudWatch" }
                  targets = [
                    {
                      refId       = "A"
                      namespace   = "GJ2026/BookReservation"
                      metricName  = "QueryCount"
                      statistic   = "Sum"
                      dimensions  = {}
                      matchExact  = false
                      region      = var.aws_region
                    },
                  ]
                },
              ]
              schemaVersion = 39
            })
          }
        }
      }
    }),
  ]
}