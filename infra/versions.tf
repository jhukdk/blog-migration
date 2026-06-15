terraform {
  # use_lockfile (S3 native state locking) requires Terraform >= 1.10.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50"
    }
  }

  # Remote state in the pre-existing bucket (created manually, not by this code).
  backend "s3" {
    bucket       = "jhuk-tech-tfstate-877995959706"
    key          = "jhuk/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
