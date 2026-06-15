# ACM certificate for the eventual custom domain. Created now so the validation
# CNAME is available (via outputs) to add at Namecheap, but NOT attached to the
# CloudFront distribution yet. DNS validation records are NOT created here —
# DNS is managed manually at Namecheap.
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Gate that confirms the cert is validated/ISSUED before CloudFront attaches it.
# No validation_record_fqdns: the validation CNAME lives at Namecheap (not managed
# by Terraform), so this just waits on ACM status rather than creating DNS records.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn = aws_acm_certificate.this.arn
}
