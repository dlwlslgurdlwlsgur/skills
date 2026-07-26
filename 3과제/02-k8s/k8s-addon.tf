# 1. AWS ALB 컨트롤러 공식 IAM 정책 JSON 파일 다운로드
data "http" "alb_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json"
}

# 2. 다운로드한 JSON 기반으로 IAM 정책 생성
resource "aws_iam_policy" "alb_controller_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy-TF"
  policy = data.http.alb_policy.response_body
}

# 3. EKS OIDC Provider 정보 조회
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# 4. ALB 컨트롤러가 사용할 IAM Role (IRSA) 신뢰 정책 생성
data "aws_iam_policy_document" "alb_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }
  }
}

# 5. IAM Role 생성 및 정책 연결
resource "aws_iam_role" "alb_controller_role" {
  name               = "AmazonEKSLoadBalancerControllerRole-TF"
  assume_role_policy = data.aws_iam_policy_document.alb_assume_role.json
}

resource "aws_iam_role_policy_attachment" "alb_controller_attach" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}

# 6. ALB 컨트롤러 Helm 배포 (생성된 IAM Role 자동 주입)
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = data.aws_eks_cluster.cluster.name
  }

  set {
    name  = "serviceAccount.create"
    value = "true" 
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # 테라폼으로 만든 IAM Role을 ServiceAccount 어노테이션에 주입
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller_role.arn
  }
  
  set {
    name  = "vpcId"
    value = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id 
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  depends_on = [ aws_iam_role_policy_attachment.alb_controller_attach ]
}

# 7. Metrics Server 배포 (기존 유지)
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}