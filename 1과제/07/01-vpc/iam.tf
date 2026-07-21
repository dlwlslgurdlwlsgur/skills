### EKS cluster role ###
data "aws_iam_policy_document" "eks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "unicorn-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

### EKS node roles (App / Addon) ###
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  node_role_managed_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
  ]
}

resource "aws_iam_role" "eks_node" {
  for_each = toset(["addon", "app"])

  name               = "unicorn-eks-${each.key}-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = { for pair in setproduct(["addon", "app"], local.node_role_managed_policies) : "${pair[0]}-${pair[1]}" => pair }

  role       = aws_iam_role.eks_node[each.value[0]].name
  policy_arn = each.value[1]
}

### Pod Identity: 공통 신뢰정책 - "본 클러스터에서만 사용 가능" (SourceArn 고정) ###
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_eks_cluster.this.arn]
    }
  }
}

### Book App Pod Identity Role: DynamoDB PutItem + App CMK 사용 (최소 권한, 요구사항 8-Security) ###
resource "aws_iam_role" "book_app" {
  name               = "unicorn-book-app-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "book_app_policy" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.concert_db.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.app.arn]
  }
}

resource "aws_iam_role_policy" "book_app" {
  name   = "unicorn-book-app-policy"
  role   = aws_iam_role.book_app.id
  policy = data.aws_iam_policy_document.book_app_policy.json
}

### Fluent Bit Pod Identity Role: CloudWatch Logs 전송 ###
resource "aws_iam_role" "fluent_bit" {
  name               = "unicorn-fluent-bit-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "fluent_bit_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.book_app.arn,
      "${aws_cloudwatch_log_group.book_app.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "fluent_bit" {
  name   = "unicorn-fluent-bit-policy"
  role   = aws_iam_role.fluent_bit.id
  policy = data.aws_iam_policy_document.fluent_bit_policy.json
}

### Grafana Pod Identity Role: CloudWatch(ALB latency) 메트릭 조회 ###
resource "aws_iam_role" "grafana" {
  name               = "unicorn-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "grafana_policy" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarmsForMetric",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana" {
  name   = "unicorn-grafana-policy"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana_policy.json
}

### AWS Load Balancer Controller Pod Identity Role ###
resource "aws_iam_role" "lbc" {
  name               = "unicorn-aws-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "lbc" {
  name   = "unicorn-aws-lb-controller-policy"
  role   = aws_iam_role.lbc.id
  policy = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
}

### Lambda 실행 역할: DynamoDB 조회 + 로그 (요구사항 9) ###
resource "aws_iam_role" "lambda_get_booking" {
  name = "unicorn-lambda-get-booking-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

data "aws_iam_policy_document" "lambda_get_booking_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.concert_db.arn,
      "${aws_dynamodb_table.concert_db.arn}/index/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.app.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/unicorn/lambda/get-booking:*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_replica_key.platform_replica.arn]
  }
}

resource "aws_iam_role_policy" "lambda_get_booking" {
  name   = "unicorn-lambda-get-booking-policy"
  role   = aws_iam_role.lambda_get_booking.id
  policy = data.aws_iam_policy_document.lambda_get_booking_policy.json
}
