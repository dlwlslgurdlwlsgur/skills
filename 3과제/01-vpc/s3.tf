data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "main" {
  # 12345 대신 동적으로 계정 ID(account_id)를 삽입
  bucket        = "${var.project_name}-app-data-bucket-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}