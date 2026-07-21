resource "helm_release" "kube_prometheus_stack" {
  name       = "unicorn-monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "67.9.0"
  timeout    = 900

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

  # ---------------------------------------------------------
  # 1. ECR 프라이빗 이미지 사용 (Grafana 메인 컨테이너)
  # ---------------------------------------------------------
  set {
    name  = "grafana.image.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }
  set {
    name  = "grafana.image.repository"
    value = "grafana" # 만약 ECR 리포지토리 이름을 'grafana/grafana'로 만드셨다면 해당 이름으로 변경하세요.
  }
  set {
    name  = "grafana.image.tag"
    value = "11.4.0"
  }
  
  # ---------------------------------------------------------
  # 2. ECR 프라이빗 이미지 사용 (Dashboard 다운로더)
  # ---------------------------------------------------------
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

  # ---------------------------------------------------------
  # 3. ConfigMap 감지용 K8s 사이드카 컨테이너 (🚨 수정 완료!)
  # ---------------------------------------------------------
  set {
    name  = "grafana.sidecar.image.registry"
    value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  }
  set {
    name  = "grafana.sidecar.image.repository"
    value = "kiwigrid/k8s-sidecar" # ❌ 기존 curlimages/curl 에서 올바른 이미지로 변경
  }
  set {
    name  = "grafana.sidecar.image.tag"
    value = "1.28.0"               # ❌ 기존 8.9.1 에서 1.28.0 으로 변경
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
        {
          id         = 1
          title      = "EKS Node CPU Usage (%)"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              refId        = "A"
              expr         = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
              legendFormat = "{{instance}}"
            },
          ]
        },
        {
          id         = 2
          title      = "EKS Node Memory Usage (%)"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              refId        = "A"
              expr         = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"
              legendFormat = "{{instance}}"
            },
          ]
        },
        {
          id         = 3
          title      = "unicorn Namespace Pod Status"
          type       = "stat"
          gridPos    = { h = 8, w = 8, x = 0, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          options = {
            graphMode     = "area"
            colorMode     = "value"
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
        {
          id         = 4
          title      = "Book App Ready Pods"
          type       = "stat"
          gridPos    = { h = 8, w = 4, x = 8, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          fieldConfig = {
            defaults = { displayName = "ready" }
          }
          options = {
            graphMode     = "none"
            reduceOptions = { calcs = ["lastNotNull"] }
          }
          targets = [
            {
              refId = "A"
              expr  = "sum(kube_deployment_status_replicas_ready{namespace=\"unicorn\",deployment=\"unicorn-book-app-deploy\"})"
            },
          ]
        },
        {
          id         = 5
          title      = "Book App HTTP Request Duration"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 8 }
          datasource = { type = "cloudwatch", uid = "cloudwatch" }
          targets = [
            {
              refId      = "p50"
              region     = var.aws_region
              namespace  = "AWS/ApplicationELB"
              metricName = "TargetResponseTime"
              statistic  = "p50"
              dimensions = { LoadBalancer = data.aws_lb.this.arn_suffix }
            },
            {
              refId      = "p95"
              region     = var.aws_region
              namespace  = "AWS/ApplicationELB"
              metricName = "TargetResponseTime"
              statistic  = "p95"
              dimensions = { LoadBalancer = data.aws_lb.this.arn_suffix }
            },
            {
              refId      = "p99"
              region     = var.aws_region
              namespace  = "AWS/ApplicationELB"
              metricName = "TargetResponseTime"
              statistic  = "p99"
              dimensions = { LoadBalancer = data.aws_lb.this.arn_suffix }
            },
          ]
        },
      ]
    })
  }

  depends_on = [helm_release.kube_prometheus_stack]
}