data "archive_file" "lambda_reservation" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/build/lambda_reservation.zip"
}

resource "aws_lambda_function" "reservation" {
  function_name    = "gj2026-book-reservation"
  role             = aws_iam_role.lambda_reservation.arn
  runtime          = "python3.14"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda_reservation.output_path
  source_code_hash = data.archive_file.lambda_reservation.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.books.name
    }
  }
}

resource "aws_lambda_function_url" "reservation" {
  function_name      = aws_lambda_function.reservation.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "function_url_public" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.reservation.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}