# Public hosted zone for jhuk.tech. DNS hosting moves from Namecheap to Route 53;
# the domain stays registered at Namecheap. After `apply`, set the four nameservers
# from the `route53_name_servers` output as Custom DNS at the Namecheap registrar.
resource "aws_route53_zone" "this" {
  name = var.domain_name
}

locals {
  # CloudFront's fixed hosted-zone ID for alias records (a global AWS constant).
  cloudfront_hosted_zone_id = "Z2FDTNDATAQYW2"

  # Apex + www, both IPv4 (A) and IPv6 (AAAA). Aliases track the distribution
  # automatically — no hardcoded CloudFront IPs, which is what broke the apex.
  site_aliases = {
    "apex-a"    = { name = var.domain_name, type = "A" }
    "apex-aaaa" = { name = var.domain_name, type = "AAAA" }
    "www-a"     = { name = "www.${var.domain_name}", type = "A" }
    "www-aaaa"  = { name = "www.${var.domain_name}", type = "AAAA" }
  }
}

resource "aws_route53_record" "site" {
  for_each = local.site_aliases

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = local.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}
