locals {
  ecr_public_mirror = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ecr-public"
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = data.aws_eks_cluster.this.name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.aws_eks_cluster.this.vpc_config[0].vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lbc.metadata[0].name
  }

  set {
    name  = "image.repository"
    value = "${local.ecr_public_mirror}/eks/aws-load-balancer-controller"
  }

  set {
    name  = "image.tag"
    value = "v2.13.4"
  }

  set {
    name  = "nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "gj2026-eks-addon-nodegroup"
  }
}