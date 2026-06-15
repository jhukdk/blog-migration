# Everything (content bucket, CloudFront, and the ACM cert it will eventually use)
# must live in us-east-1, so a single default provider is sufficient.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
