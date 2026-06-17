# AWS WAFv2 web ACL fronting the CloudFront distribution. A CLOUDFRONT-scoped
# web ACL (and its logging) must live in us-east-1 — which the single default
# provider already targets. Attached to the distribution via web_acl_id in
# cloudfront.tf. Default action is allow; only the rules below block.
resource "aws_wafv2_web_acl" "this" {
  name        = "jhuk-tech-cloudfront"
  description = "Edge WAF for the jhuk.tech CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS-managed baseline protections (common exploit patterns, bad inputs).
  # override_action { none {} } keeps each managed rule's own action.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "jhuk-tech-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # Rate-based rule: block any single source IP that exceeds the threshold
  # within the 5-minute (300s) evaluation window.
  rule {
    name     = "RateLimitPerIP"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "jhuk-tech-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "jhuk-tech-web-acl"
    sampled_requests_enabled   = true
  }
}

# Destination log group for WAF logs. The name MUST start with "aws-waf-logs-"
# or AWS WAF rejects it as a logging destination.
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-jhuk-tech-cloudfront"
  retention_in_days = 30
}

# Enable WAF logging to the CloudWatch log group above. The .arn attribute on
# aws_cloudwatch_log_group already omits the trailing ":*", which WAF requires.
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}
