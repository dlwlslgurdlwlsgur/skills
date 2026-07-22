resource "aws_cloudwatch_log_group" "lambda_get_booking" {
  name              = "/unicorn/lambda/get-booking"
  retention_in_days = 30
  kms_key_id        = aws_kms_replica_key.platform_replica.arn
  tags              = local.common_tags
}

data "archive_file" "lambda_get_booking" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_booking.py"
  output_path = "${path.module}/build/lambda_get_booking.zip"
}

resource "aws_lambda_function" "get_booking" {
  function_name    = "unicorn-get-booking-func"
  role             = aws_iam_role.lambda_get_booking.arn
  runtime          = "python3.13"
  handler          = "get_booking.handler"
  filename         = data.archive_file.lambda_get_booking.output_path
  source_code_hash = data.archive_file.lambda_get_booking.output_base64sha256
  timeout          = 10
  kms_key_arn      = aws_kms_replica_key.platform_replica.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.concert_db.name
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_get_booking.name
  }

  tags = merge(local.common_tags, { Name = "unicorn-get-booking-func" })

  depends_on = [aws_cloudwatch_log_group.lambda_get_booking]
}
