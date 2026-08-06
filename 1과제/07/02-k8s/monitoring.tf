data "aws_lb" "unicorn_alb" {
  name = "unicorn-alb"
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "unicorn-monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "67.9.0"
  timeout    = 900

  set {
    name  = "grafana.defaultDashboardsEnabled"
    value = "false"
  }

  set {
    name  = "kubeControllerManager.enabled"
    value = "false"
  }
  set {
    name  = "kubeScheduler.enabled"
    value = "false"
  }
  set {
    name  = "kubeEtcd.enabled"
    value = "false"
  }

  set {
    name  = "prometheusOperator.nodeSelector.unicorn"
    value = "addon"
  }
  set {
    name  = "prometheus.prometheusSpec.nodeSelector.unicorn"
    value = "addon"
  }
  set {
    name  = "kube-state-metrics.nodeSelector.unicorn"
    value = "addon"
  }

  set {
    name  = "grafana.nodeSelector.unicorn"
    value = "addon"
  }
  set {
    name  = "grafana.adminUser"
    value = local.grafana_admin_username
  }
  set {
    name  = "grafana.adminPassword"
    value = local.grafana_admin_password
  }
  set {
    name  = "grafana.service.type"
    value = "ClusterIP"
  }
  set {
    name  = "grafana.persistence.enabled"
    value = "false"
  }

  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }
  set {
    name  = "grafana.sidecar.dashboards.label"
    value = "grafana_dashboard"
  }

  set {
    name  = "grafana.image.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }
  set {
    name  = "grafana.image.repository"
    value = "grafana"
  }
  set {
    name  = "grafana.image.tag"
    value = "11.4.0"
  }
  
  set {
    name  = "grafana.downloadDashboardsImage.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }
  set {
    name  = "grafana.downloadDashboardsImage.repository"
    value = "curlimages/curl"
  }
  set {
    name  = "grafana.downloadDashboardsImage.tag"
    value = "8.9.1"
  }

  set {
    name  = "grafana.sidecar.image.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }
  set {
    name  = "grafana.sidecar.image.repository"
    value = "kiwigrid/k8s-sidecar"
  }
  set {
    name  = "grafana.sidecar.image.tag"
    value = "1.28.0"
  }

  values = [
    yamlencode({
      grafana = {
        additionalDataSources = [
          {
            name      = "CloudWatch"
            uid       = "cloudwatch"
            type      = "cloudwatch"
            access    = "proxy"
            isDefault = false
            jsonData = {
              authType      = "default"
              defaultRegion = var.aws_region
            }
          },
        ]
      }
    }),
  ]
}

resource "kubernetes_config_map" "grafana_dashboard" {
  metadata {
    name      = "unicorn-grafana-dashboard"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { grafana_dashboard = "1" }
  }

  data = {
    "unicorn-grafana-dashboard.json" = jsonencode({
      title         = "unicorn-grafana-dashboard"
      uid           = "unicorn-grafana-dashboard"
      time          = { from = "now-1h", to = "now" }
      refresh       = "10s"
      schemaVersion = 39
      panels = [
        # 1. EKS Node CPU Usage (%)
        {
          id         = 1
          title      = "EKS Node CPU Usage (%)"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          fieldConfig = {
            defaults = {
              unit = "percent"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "green", value = null },
                  { color = "yellow", value = 60 },
                  { color = "red", value = 80 }
                ]
              }
            }
          }
          options = {
            legend = {
              displayMode = "table"
              placement   = "right"
              calcs       = ["mean", "max", "lastNotNull"]
            }
          }
          targets = [
            {
              refId        = "A"
              expr         = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
              legendFormat = "{{instance}}"
            },
          ]
        },
        # 2. EKS Node Memory Usage (%)
        {
          id         = 2
          title      = "EKS Node Memory Usage (%)"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          fieldConfig = {
            defaults = {
              unit = "percent"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "green", value = null },
                  { color = "yellow", value = 70 },
                  { color = "red", value = 85 }
                ]
              }
            }
          }
          options = {
            legend = {
              displayMode = "table"
              placement   = "right"
              calcs       = ["mean", "max", "lastNotNull"]
            }
          }
          targets = [
            {
              refId        = "A"
              expr         = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"
              legendFormat = "{{instance}}"
            },
          ]
        },
        # 3. unicorn Namespace Pod Status
        {
          id         = 3
          title      = "unicorn Namespace Pod Status"
          type       = "stat"
          gridPos    = { h = 8, w = 8, x = 0, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          fieldConfig = {
            defaults = {
              color = { mode = "thresholds" }
            }
            overrides = [
              { matcher = { id = "byName", options = "Failed" }, properties = [{ id = "color", value = { mode = "fixed", fixedColor = "red" } }] },
              { matcher = { id = "byName", options = "Pending" }, properties = [{ id = "color", value = { mode = "fixed", fixedColor = "yellow" } }] },
              { matcher = { id = "byName", options = "Running" }, properties = [{ id = "color", value = { mode = "fixed", fixedColor = "green" } }] },
              { matcher = { id = "byName", options = "Succeeded" }, properties = [{ id = "color", value = { mode = "fixed", fixedColor = "blue" } }] },
              { matcher = { id = "byName", options = "Unknown" }, properties = [{ id = "color", value = { mode = "fixed", fixedColor = "purple" } }] }
            ]
          }
          options = {
            graphMode     = "area"
            colorMode     = "value"
            textMode      = "valueAndName"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
          targets = [
            { refId = "A", expr = "sum(kube_pod_status_phase{namespace=\"unicorn\",phase=\"Failed\"})", legendFormat = "Failed" },
            { refId = "B", expr = "sum(kube_pod_status_phase{namespace=\"unicorn\",phase=\"Pending\"})", legendFormat = "Pending" },
            { refId = "C", expr = "sum(kube_pod_status_phase{namespace=\"unicorn\",phase=\"Running\"})", legendFormat = "Running" },
            { refId = "D", expr = "sum(kube_pod_status_phase{namespace=\"unicorn\",phase=\"Succeeded\"})", legendFormat = "Succeeded" },
            { refId = "E", expr = "sum(kube_pod_status_phase{namespace=\"unicorn\",phase=\"Unknown\"})", legendFormat = "Unknown" },
          ]
        },
        # 4. Book App Ready Pods
        {
          id         = 4
          title      = "Book App Ready Pods"
          type       = "stat"
          gridPos    = { h = 8, w = 4, x = 8, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          fieldConfig = {
            defaults = { 
              displayName = "ready"
              color       = { mode = "fixed", fixedColor = "yellow" } 
            }
          }
          options = {
            graphMode     = "none"
            colorMode     = "value"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
          targets = [
            {
              refId = "A"
              expr  = "sum(kube_deployment_status_replicas_ready{namespace=\"unicorn\",deployment=\"unicorn-book-app-deploy\"})"
            },
          ]
        },
        # 5. Book App HTTP Request Duration
        {
          id         = 5
          title      = "Book App HTTP Request Duration"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 8 }
          datasource = { type = "cloudwatch", uid = "cloudwatch" }
          fieldConfig = {
            defaults = {
              unit = "s"
            }
          }
          options = {
            legend = {
              displayMode = "table"
              placement   = "bottom"
              calcs       = ["mean", "max", "lastNotNull"]
            }
          }
          targets = [
            {
              refId      = "p50"
              region     = var.aws_region
              namespace  = "AWS/ApplicationELB"
              metricName = "TargetResponseTime"
              statistic  = "p50"
              period     = 60
              matchExact = false
              dimensions = {
                LoadBalancer = data.aws_lb.unicorn_alb.arn_suffix
                TargetGroup  = data.aws_lb_target_group.book.arn_suffix
              }
              "accountId": "default"
            },
            {
              refId      = "p95"
              region     = var.aws_region
              namespace  = "AWS/ApplicationELB"
              metricName = "TargetResponseTime"
              statistic  = "p95"
              period     = 60
              matchExact = false
              dimensions = {
                LoadBalancer = data.aws_lb.unicorn_alb.arn_suffix
                TargetGroup  = data.aws_lb_target_group.book.arn_suffix
              }
              "accountId": "default"
            },
            {
              refId      = "p99"
              region     = var.aws_region
              namespace  = "AWS/ApplicationELB"
              metricName = "TargetResponseTime"
              statistic  = "p99"
              period     = 60
              matchExact = false
              dimensions = {
                LoadBalancer = data.aws_lb.unicorn_alb.arn_suffix
                TargetGroup  = data.aws_lb_target_group.book.arn_suffix
              }
              "accountId": "default"
            },
          ]
        },
      ]
    })
  }

  depends_on = [helm_release.kube_prometheus_stack]
}