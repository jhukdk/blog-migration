# Origin Access Control — lets CloudFront sign requests to the private S3 bucket.
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.content_bucket_name}-oac"
  description                       = "OAC for the jhuk.tech content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Viewer-request function that resolves Hugo's pretty URLs to S3 object keys.
resource "aws_cloudfront_function" "rewrite_index" {
  name    = "jhuk-tech-rewrite-index"
  runtime = "cloudfront-js-2.0"
  comment = "Append index.html to directory-style request paths"
  publish = true
  code    = file("${path.module}/functions/rewrite_index.js")
}

# AWS-managed cache policy tuned for static sites (long TTLs, gzip/brotli).
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

locals {
  s3_origin_id = "s3-${var.content_bucket_name}"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "jhuk.tech static site"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # Edge WAF (AWS-managed common rules + per-IP rate limit). CLOUDFRONT-scoped
  # web ACLs are attached by ARN. Defined in waf.tf.
  web_acl_id = aws_wafv2_web_acl.this.arn

  # Custom domains served by this distribution. Must be a subset of the ACM cert's
  # names; derived from the same vars so aliases and cert SANs stay in lockstep.
  aliases = concat([var.domain_name], var.subject_alternative_names)

  # Standard access logging → the logs bucket owned by the
  # splunk-enterprise-integration repo, where Splunk ingests it. `bucket` here is
  # the S3 bucket DOMAIN (bucket.s3.amazonaws.com), not the bare name. That bucket
  # must already exist with ACLs enabled and the awslogsdelivery grant (handled in
  # the other repo) — apply it first, or this apply fails. include_cookies=false:
  # this is a static site, cookies add nothing to the access logs.
  logging_config {
    bucket          = "${var.cf_logs_bucket_name}.s3.amazonaws.com"
    include_cookies = false
    prefix          = "cloudfront/"
  }

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }
  }

  # The OAC principal is granted s3:ListBucket (see s3.tf), so S3 returns a true
  # 404 for missing keys. Map that to Hugo's /404.html. 403 is intentionally NOT
  # remapped so genuine forbidden responses (e.g. WAF blocks) surface as 403.
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Attach the validated ACM cert via SNI with a modern TLS floor. References the
  # validation resource so the cert is only attached once ACM reports it ISSUED.
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
