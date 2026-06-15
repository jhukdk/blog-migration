variable "aws_region" {
  description = "AWS region. CloudFront + its ACM cert require us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Primary site domain (ACM certificate subject)."
  type        = string
  default     = "jhuk.tech"
}

variable "subject_alternative_names" {
  description = "Additional names on the ACM certificate."
  type        = list(string)
  default     = ["www.jhuk.tech"]
}

variable "content_bucket_name" {
  description = "Name of the private S3 bucket that holds the built Hugo site."
  type        = string
  default     = "jhuk-tech-content-877995959706"
}

variable "github_repo" {
  description = "GitHub repo (owner/name) whose Actions can assume the deploy role."
  type        = string
  default     = "jhukdk/blog-migration"
}

variable "github_oidc_subjects" {
  description = <<-EOT
    Allowed values for the GitHub OIDC `sub` claim. Defaults to deploys from the
    main branch only (least privilege). Use "repo:owner/name:*" to allow any ref.
  EOT
  type        = list(string)
  default     = ["repo:jhukdk/blog-migration:ref:refs/heads/main"]
}

variable "tags" {
  description = "Tags applied to all resources via the provider default_tags."
  type        = map(string)
  default = {
    Project   = "jhuk-tech"
    ManagedBy = "terraform"
  }
}
