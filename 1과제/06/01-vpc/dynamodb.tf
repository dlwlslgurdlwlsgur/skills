resource "aws_dynamodb_table" "books" {
  name         = "books"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "booking_id"

  attribute {
    name = "booking_id"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  global_secondary_index {
    name            = "client_id-index"
    hash_key        = "client_id"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.db.arn
  }
}

resource "aws_dynamodb_resource_policy" "books_write_restriction" {
  resource_arn = aws_dynamodb_table.books.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyWriteExceptBookApp"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = [
          aws_dynamodb_table.books.arn,
          "${aws_dynamodb_table.books.arn}/index/*",
        ]
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