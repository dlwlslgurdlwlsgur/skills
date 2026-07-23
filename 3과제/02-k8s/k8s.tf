resource "kubernetes_deployment" "product" {
  metadata {
    name = "product-app"
    labels = { app = "product" }
  }
  spec {
    # 기존에 고정해뒀던 replicas = 2 는 삭제하거나 주석 처리합니다. (이제 HPA가 관리함)
    # replicas = 2 
    
    selector {
      match_labels = { app = "product" }
    }
    template {
      metadata {
        labels = { app = "product" }
      }
      spec {
        container {
          name  = "product"
          image = "${data.terraform_remote_state.base.outputs.ecr_product_url}:latest"
          port {
            container_port = 8080
          }
          
          # [핵심] HPA가 작동하기 위한 리소스 기준치 설정
          resources {
            requests = {
              cpu    = "100m"   # 평소에 이만큼은 무조건 보장
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"   # 트래픽 몰려도 이 이상은 쓰지 못하게 제한
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# (기존 product_svc 서비스 코드는 그대로 유지)

# [핵심] 오토스케일링 규칙 (HPA) 설정
resource "kubernetes_horizontal_pod_autoscaler_v2" "product_hpa" {
  metadata {
    name = "product-hpa"
  }

  spec {
    min_replicas = 1  # ⭐️ 평소(저비용): 트래픽이 없으면 1개로 줄여서 과금 최소화
    max_replicas = 5  # ⭐️ 폭주(안정성): 트래픽이 몰리면 최대 5개까지 자동으로 늘림

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.product.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 50  # CPU 사용량이 50%를 넘어가면 스케일 아웃(앱 추가) 시작
        }
      }
    }
  }
}