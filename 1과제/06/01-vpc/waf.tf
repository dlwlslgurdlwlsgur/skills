resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1
  name     = "gj2026-waf-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "method-not-allowed"
    content      = "Method Not Allowed"
    content_type = "TEXT_PLAIN"
  }

  custom_response_body {
    key          = "access-denied"
    content      = "Access Deined"
    content_type = "TEXT_PLAIN"
  }

  rule {
    name     = "restrict-book-method"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 405
          custom_response_body_key = "method-not-allowed"
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            positional_constraint = "STARTS_WITH"
            search_string          = "/v1/book"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  method {}
                }
                positional_constraint = "EXACTLY"
                search_string          = "POST"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "gj2026-restrict-book-method"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "restrict-reservation-client-id"
    priority = 2

    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "access-denied"
        }
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            positional_constraint = "STARTS_WITH"
            search_string          = "/reservation"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          regex_match_statement {
            regex_string = "(^|&)client_id="
            field_to_match {
              query_string {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              regex_match_statement {
                regex_string = "^[A-Za-z][0-9]+$"
                field_to_match {
                  single_query_argument {
                    name = "client_id"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "gj2026-restrict-reservation-client-id"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "gj2026-waf-acl"
    sampled_requests_enabled   = true
  }
}
