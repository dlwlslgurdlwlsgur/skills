resource "aws_cloudwatch_log_group" "book_app" {
  name              = "/unicorn/eks/book-app"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform_replica.arn
  tags              = local.common_tags
}