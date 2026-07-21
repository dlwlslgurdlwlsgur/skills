resource "kubernetes_namespace" "skills" {
  metadata {
    name = "skills"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "logging" {
  metadata {
    name = "logging"
  }
}

resource "kubernetes_service_account" "book_app" {
  metadata {
    name      = "book-app"
    namespace = kubernetes_namespace.skills.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = data.aws_iam_role.book_app.arn
    }
  }
}

resource "kubernetes_service_account" "lbc" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.aws_iam_role.lbc.arn
    }
  }
}

resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = "aws-for-fluent-bit"
    namespace = kubernetes_namespace.logging.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = data.aws_iam_role.fluent_bit.arn
    }
  }
}

resource "kubernetes_service_account" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = data.aws_iam_role.grafana.arn
    }
  }
}

resource "kubernetes_deployment" "book" {
  metadata {
    name      = "book"
    namespace = kubernetes_namespace.skills.metadata[0].name
    labels    = { app = "book" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "book" }
    }

    template {
      metadata {
        labels = { app = "book" }
      }

      spec {
        service_account_name = kubernetes_service_account.book_app.metadata[0].name

        container {
          name  = "book"
          image = "${data.aws_ecr_repository.book.repository_url}:latest"

          port {
            container_port = 8080
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          env {
            name  = "TABLE_NAME"
            value = var.dynamodb_table_name
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "book" {
  metadata {
    name      = "book-svc"
    namespace = kubernetes_namespace.skills.metadata[0].name
  }

  spec {
    selector = { app = "book" }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_network_policy" "book_alb_only" {
  metadata {
    name      = "book-allow-from-alb-only"
    namespace = kubernetes_namespace.skills.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = { app = "book" }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        ip_block {
          cidr = var.vpc_cidr
        }
      }

      ports {
        port     = 8080
        protocol = "TCP"
      }
    }
  }
}