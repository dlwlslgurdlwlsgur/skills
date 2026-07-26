# 1. skills 네임스페이스 생성
resource "kubernetes_namespace" "skills" {
  metadata {
    name = "skills"
  }
}

# ==========================================
# [앱 1] Product 배포 및 서비스
# ==========================================
resource "kubernetes_deployment" "product" {
  wait_for_rollout = false 
  metadata {
    name      = "product-app"
    namespace = kubernetes_namespace.skills.metadata[0].name
    labels    = { app = "product" }
  }
  spec {
    selector { match_labels = { app = "product" } }
    template {
      metadata { labels = { app = "product" } }
      spec {
        container {
          name  = "product"
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-northeast-2.amazonaws.com/contest-product:latest"
          port { container_port = 8080 }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "200m", memory = "256Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "product_svc" {
  metadata {
    name      = "product-svc"
    namespace = kubernetes_namespace.skills.metadata[0].name
  }
  spec {
    selector = { app = "product" }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# ==========================================
# [앱 2] User 배포 및 서비스 (예시)
# ==========================================
resource "kubernetes_deployment" "user" {
  wait_for_rollout = false 
  metadata {
    name      = "user-app"
    namespace = kubernetes_namespace.skills.metadata[0].name
    labels    = { app = "user" }
  }
  spec {
    selector { match_labels = { app = "user" } }
    template {
      metadata { labels = { app = "user" } }
      spec {
        container {
          name  = "user"
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-northeast-2.amazonaws.com/contest-user:latest"
          port { container_port = 8080 }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "200m", memory = "256Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "user_svc" {
  metadata {
    name      = "user-svc"
    namespace = kubernetes_namespace.skills.metadata[0].name
  }
  spec {
    selector = { app = "user" }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# ==========================================
# [앱 3] Order 배포 및 서비스 (예시)
# ==========================================
resource "kubernetes_deployment" "order" {
  wait_for_rollout = false 
  metadata {
    name      = "order-app"
    namespace = kubernetes_namespace.skills.metadata[0].name
    labels    = { app = "order" }
  }
  spec {
    selector { match_labels = { app = "order" } }
    template {
      metadata { labels = { app = "order" } }
      spec {
        container {
          name  = "order"
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-northeast-2.amazonaws.com/contest-order:latest"
          port { container_port = 8080 }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "200m", memory = "256Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "order_svc" {
  metadata {
    name      = "order-svc"
    namespace = kubernetes_namespace.skills.metadata[0].name
  }
  spec {
    selector = { app = "order" }
    port {
      port        = 80
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# ==========================================
# AWS ALB Ingress 설정 (3개 앱 라우팅)
# ==========================================
resource "kubernetes_ingress_v1" "main_ingress" {
  metadata {
    name      = "main-alb"
    namespace = kubernetes_namespace.skills.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {
    rule {
      http {
        # 1. /product 경로로 들어오면 product_svc로 연결
        path {
          path      = "/product"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.product_svc.metadata[0].name
              port { number = 80 }
            }
          }
        }
        # 2. /user 경로로 들어오면 user_svc로 연결
        path {
          path      = "/user"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.user_svc.metadata[0].name
              port { number = 80 }
            }
          }
        }
        # 3. /order 경로로 들어오면 order_svc로 연결
        path {
          path      = "/order"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.order_svc.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}