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

  # No custom domain yet — serve on the default *.cloudfront.net name. The ACM
  # cert in acm.tf is created but intentionally NOT attached here.
  aliases = []

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

  # The private bucket returns 403 (not 404) for missing keys because ListBucket
  # is not granted, so map both to Hugo's /404.html with a 404 status.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

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

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
