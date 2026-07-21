data "aws_caller_identity" "current" {}

resource "aws_kms_key" "db" {
  description         = "gj2026 DynamoDB CMK"
  enable_key_rotation = true
}

resource "aws_kms_alias" "db" {
  name          = "alias/gj2026-db-key"
  target_key_id = aws_kms_key.db.key_id
}

resource "aws_kms_key" "db" {
  description             = "KMS key for DynamoDB books table"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM Root Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid       = "DenyGenerateDataKeyExceptBookApp"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "kms:GenerateDataKey*",
          "kms:Encrypt"
        ]
        Resource  = "*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = aws_iam_role.book_app.arn
          }
          ArnNotLike = {
            "aws:PrincipalArn" = "arn:aws:sts::*:assumed-role/${aws_iam_role.book_app.name}/*"
          }
        }
      }
    ]
  })
}

resource "aws_kms_key" "eks" {
  description         = "gj2026 EKS secrets envelope encryption CMK"
  enable_key_rotation = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/gj2026-eks-key"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_key" "s3" {
  description         = "gj2026 S3 static hosting CMK"
  enable_key_rotation = true
}

resource "aws_kms_alias" "s3" {
  name          = "alias/gj2026-s3-key"
  target_key_id = aws_kms_key.s3.key_id
}