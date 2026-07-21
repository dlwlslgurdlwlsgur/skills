resource "aws_eks_cluster" "this" {
  name     = "gj2026-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_node["addon"].arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = aws_iam_role.eks_node["app"].arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
    ])
  }

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.addon]

  configuration_values = jsonencode({
    nodeSelector = {
      "eks.amazonaws.com/nodegroup" = "gj2026-eks-addon-nodegroup"
    }
  })
}

resource "aws_launch_template" "addon" {
  name = "gj2026-eks-addon-lt"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "gj2026-eks-addon-node"
    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
}

resource "aws_launch_template" "app" {
  name = "gj2026-eks-app-lt"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "gj2026-eks-app-node"
    }
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gj2026-eks-addon-nodegroup"
  node_role_arn   = aws_iam_role.eks_node["addon"].arn
  subnet_ids      = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  launch_template {
    id      = aws_launch_template.addon.id
    version = aws_launch_template.addon.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node,
    kubernetes_config_map.aws_auth,
  ]
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gj2026-eks-app-nodegroup"
  node_role_arn   = aws_iam_role.eks_node["app"].arn
  subnet_ids      = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  ami_type        = "BOTTLEROCKET_x86_64"
  instance_types  = ["m5.xlarge"]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node,
    kubernetes_config_map.aws_auth,
  ]
}
