resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.base.outputs.cluster_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  
  # VPC ID를 직접 지정해 주어야 ALB가 정상적으로 생성됩니다.
  set {
    name  = "vpcId"
    value = data.terraform_remote_state.base.outputs.vpc_id # 01-base/outputs.tf에 vpc_id 출력도 추가 필요
  }
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  # 인증서 관련 오류 방지 (시험/개발 환경용)
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}