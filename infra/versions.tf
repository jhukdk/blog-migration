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
  # `bucket` is intentionally omitted here to keep the account ID out of source —
  # it is the deterministic name "jhuk-tech-tfstate-<accountid>". Supply it via
  # partial backend config at init time:
  #   terraform init -backend-config=backend.hcl
  # (copy backend.hcl.example to backend.hcl; backend.hcl is gitignored).
  backend "s3" {
    key          = "jhuk/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
