output "content_bucket_name" {
  description = "Name of the private S3 content bucket (deploy target for CI)."
  value       = aws_s3_bucket.content.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used for cache invalidation)."
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "Default *.cloudfront.net domain the site is served on."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "acm_certificate_arn" {
  description = "ARN of the (not-yet-attached) ACM certificate."
  value       = aws_acm_certificate.this.arn
}

output "acm_validation_records" {
  description = <<-EOT
    DNS validation records to add manually at Namecheap (one per cert name).
    Keyed by domain; add each as a CNAME of `name` -> `value`.
  EOT
  value = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions OIDC deploy role."
  value       = aws_iam_role.deploy.arn
}

output "route53_name_servers" {
  description = "Set these four as Custom DNS nameservers at the Namecheap registrar."
  value       = aws_route53_zone.this.name_servers
}
