data "aws_iam_policy_document" "audit_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.audit_role_external_id]
    }
  }
}

resource "aws_iam_role" "audit" {
  name                 = "unicorn-audit-role"
  assume_role_policy   = data.aws_iam_policy_document.audit_assume.json
  max_session_duration = 3600
  tags                 = local.common_tags
}

data "aws_iam_policy_document" "audit_policy" {
  statement {
    sid    = "DynamoDbRead"
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
    sid       = "VpcDescribe"
    effect    = "Allow"
    actions   = ["ec2:DescribeVpcs"]
    resources = ["*"]
  }

  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }
}

resource "aws_iam_role_policy" "audit" {
  name   = "unicorn-audit-policy"
  role   = aws_iam_role.audit.id
  policy = data.aws_iam_policy_document.audit_policy.json
}
