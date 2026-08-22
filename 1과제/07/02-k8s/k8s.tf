resource "kubernetes_namespace" "unicorn" {
  metadata {
    name = "unicorn"
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
    name      = "unicorn-book-app-sa"
    namespace = kubernetes_namespace.unicorn.metadata[0].name
  }
}

resource "kubernetes_service_account" "lbc" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
  }
}

resource "kubernetes_service_account" "fluent_bit" {
  metadata {
    name      = "aws-for-fluent-bit"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }
}

resource "kubernetes_deployment" "book_app" {
  metadata {
    name      = "unicorn-book-app-deploy"
    namespace = kubernetes_namespace.unicorn.metadata[0].name
    labels    = { app = "unicorn-book-app" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "unicorn-book-app" }
    }

    template {
      metadata {
        labels = { app = "unicorn-book-app" }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name             = kubernetes_service_account.book_app.metadata[0].name
        node_selector                    = { unicorn = "app" }
        termination_grace_period_seconds = 45

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = { app = "unicorn-book-app" }
          }
        }

        container {
          name  = "book"
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/unicorn-concert-app:v1.0.0"

          port {
            container_port = 8080
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          env {
            name  = "TABLE_NAME"
            value = "unicorn-concert-db"
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

          lifecycle {
            pre_stop {
              exec {
                command = ["/bin/sh", "-c", "sleep 15"]
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "book_app" {
  metadata {
    name      = "unicorn-book-app-svc"
    namespace = kubernetes_namespace.unicorn.metadata[0].name
  }

  spec {
    selector = { app = "unicorn-book-app" }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}