resource "kubernetes_manifest" "book_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "unicorn-book-tgb"
      namespace = kubernetes_namespace.unicorn.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service.book_app.metadata[0].name
        port = 8080
      }
      targetGroupARN = data.aws_lb_target_group.book.arn
      targetType     = "ip"
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller, kubernetes_deployment.book_app]
}

resource "kubernetes_manifest" "grafana_tgb" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "unicorn-grafana-tgb"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = "unicorn-monitoring-grafana"
        port = 80
      }
      targetGroupARN = data.aws_lb_target_group.grafana.arn
      targetType     = "ip"
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller, helm_release.kube_prometheus_stack]
}