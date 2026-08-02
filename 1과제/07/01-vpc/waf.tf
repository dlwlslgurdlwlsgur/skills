resource "aws_cloudwatch_log_group" "waf_logs" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-unicorn"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.platform_primary.arn
  tags              = local.common_tags
}

data "aws_iam_policy_document" "waf_log_resource_policy" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf_logs.arn}:*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf_logs" {
  provider        = aws.us_east_1
  policy_name     = "unicorn-waf-logs-policy"
  policy_document = data.aws_iam_policy_document.waf_log_resource_policy.json
}

resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1
  name     = "unicorn-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "unicorn-blocked"
    content      = "Request blocked by Unicorn WAF"
    content_type = "TEXT_PLAIN"
  }

  rule {
    name     = "block-direct-booking"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "unicorn-blocked"
        }
      }
    }

    statement {
      byte_match_statement {
        field_to_match {
          body {}
        }
        positional_constraint = "CONTAINS"
        search_string         = "DIRECT"
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-direct-booking"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2
    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicorn-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicorn-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "unicorn-rate-limit"
    priority = 4

    action {
      block {
        custom_response {
          response_code            = 403
          custom_response_body_key = "unicorn-blocked"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = 50
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "unicorn-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "unicorn-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, { Name = "unicorn-waf" })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider                = aws.us_east_1
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]

  depends_on = [aws_cloudwatch_log_resource_policy.waf_logs]
}