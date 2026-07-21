resource "aws_eks_cluster" "this" {
  name     = "unicorn-eks-cluster" # 또는 ${local.name_prefix}-...
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids = concat(
      [for s in aws_subnet.public : s.id],
      [for s in aws_subnet.private : s.id]
    )
    endpoint_private_access = true
    endpoint_public_access  = var.eks_bootstrap_public_access
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_replica_key.platform_replica.arn # platform_replica로 변경
    }
  }

  # ▼ 아래 옵션들은 vpc_config나 encryption_config 밖으로 나와 있어야 합니다. ▼

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = merge(local.common_tags, { Name = "unicorn-eks-cluster" })
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.addon]

  configuration_values = jsonencode({
    nodeSelector = { unicorn = "addon" }
  })
}

# Pod Identity 연동에 필요
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
}

# 모든 노드 시간대 KST 고정 (요구사항 8)
locals {
  node_user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==BOUNDARY=="

    --==BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    timedatectl set-timezone Asia/Seoul

    --==BOUNDARY==--
  EOT
  )
}

resource "aws_launch_template" "addon" {
  name      = "unicorn-eks-addon-lt"
  user_data = local.node_user_data

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "unicorn-k8snode-addon-node" })
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = local.common_tags
}

resource "aws_launch_template" "app" {
  name      = "unicorn-eks-app-lt"
  user_data = local.node_user_data

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "unicorn-k8snode-app-node" })
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = local.common_tags
}

# Addon NodeGroup: 최소 1대, App/DaemonSet을 제외한 모든 Addon 운용
resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "unicorn-addon-nodegroup"
  node_role_arn   = aws_iam_role.eks_node["addon"].arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.medium"]
  labels          = { unicorn = "addon" }

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  launch_template {
    id      = aws_launch_template.addon.id
    version = aws_launch_template.addon.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node,
  ]

  tags = local.common_tags
}

# App NodeGroup: 가용구역별 균등 배치, 총 3대(AZ당 1대) 이상
resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "unicorn-app-nodegroup"
  node_role_arn   = aws_iam_role.eks_node["app"].arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.medium"]
  labels          = { unicorn = "app" }

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 6
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node,
  ]

  tags = local.common_tags
}

### Pod Identity Associations ###
resource "aws_eks_pod_identity_association" "book_app" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "unicorn"
  service_account = "unicorn-book-app-sa"
  role_arn        = aws_iam_role.book_app.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "logging"
  service_account = "aws-for-fluent-bit"
  role_arn        = aws_iam_role.fluent_bit.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_pod_identity_association" "grafana" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "monitoring"
  service_account = "unicorn-monitoring-grafana"
  role_arn        = aws_iam_role.grafana.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
