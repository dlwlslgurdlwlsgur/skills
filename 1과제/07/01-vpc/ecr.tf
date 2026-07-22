resource "aws_ecr_repository" "book" {
  name                 = "unicorn-concert-app"
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter_type = "WILDCARD"
    filter      = "latest"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data.arn
  }

  tags = merge(local.common_tags, { Name = "unicorn-concert-app" })
}

# docker build/push
resource "aws_ecr_repository_policy" "book" {
  repository = aws_ecr_repository.book.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowNodePull"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.eks_node["app"].arn,
            aws_iam_role.eks_node["addon"].arn,
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
      }
    ]
  })
}

resource "aws_ecr_repository" "grafana" {
  name                 = "grafana"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
}

resource "aws_ecr_repository" "curl" {
  name                 = "curlimages/curl"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
}

resource "aws_ecr_repository" "alb_controller" {
  name                 = "ecr-public/eks/aws-load-balancer-controller"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
}