resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = "logging" # Deprecated 경고 해결을 위해 문자열로 하드코딩
  }

  data = {
    "fluent-bit.conf" = templatefile("${path.module}/manifests/fluent-bit.conf.tftpl", {
      region = var.aws_region
    })
    "parsers.conf"   = file("${path.module}/manifests/parsers.conf")
    "access_log.lua" = file("${path.module}/manifests/access_log.lua")
  }
}

resource "kubernetes_daemonset" "fluent_bit" {
  metadata {
    name      = "aws-for-fluent-bit"
    namespace = "logging" # Deprecated 경고 해결을 위해 문자열로 하드코딩
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
        service_account_name = "aws-for-fluent-bit" # Deprecated 경고 해결을 위해 문자열로 하드코딩

        # DaemonSet은 Addon Nodegroup 전용 규칙에서 예외 (요구사항 8) - 모든 노드에서 수집
        toleration {
          operator = "Exists"
        }

        container {
          name  = "aws-for-fluent-bit"
          image = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { memory = "128Mi" }
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
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

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/access_log.lua"
            sub_path   = "access_log.lua"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
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

  # 에러를 발생시켰던 01-infra 리소스(aws_eks_pod_identity_association 등) 참조 depends_on 블록 완전 삭제
}