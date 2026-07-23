# 모니터링 전용 네임스페이스 생성
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# kube-prometheus-stack 배포 (중복 제거 및 설정 통합)
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "45.7.1" # 시험 환경에 맞게 버전 조정 가능

  set {
    name  = "grafana.adminPassword"
    value = "Skills2024**"
  }

  # 핵심: 쿠버네티스/노드 관련 기본 대시보드를 전부 생성하지 않음 (빈 화면으로 시작)
  set {
    name  = "defaultDashboardsEnabled"
    value = "false"
  }
}

# 가벼운 로그 수집기 (Loki + Promtail) 배포
resource "helm_release" "loki_stack" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # 이미 kube-prometheus-stack으로 Grafana를 설치했으므로, 
  # Loki 차트 안에 있는 내장 Grafana는 끄고(false) 로그 수집 기능만 켭니다.
  set {
    name  = "grafana.enabled"
    value = "false"
  }

  # Promtail(각 파드에서 로그를 가볍게 긁어오는 에이전트) 활성화
  set {
    name  = "promtail.enabled"
    value = "true"
  }
}