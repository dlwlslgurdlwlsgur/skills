resource "kubernetes_manifest" "book_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "gj2026-book-tgb"
      namespace = kubernetes_namespace.skills.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service.book.metadata[0].name
        port = 8080
      }
      targetGroupARN = data.aws_lb_target_group.book.arn
      targetType     = "ip"
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "kubernetes_manifest" "grafana_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "gj2026-grafana-tgb"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = "grafana"
        port = 3000
      }
      targetGroupARN = data.aws_lb_target_group.grafana.arn
      targetType     = "ip"
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller, helm_release.grafana]
}