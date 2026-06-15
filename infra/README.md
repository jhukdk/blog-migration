# infra — Terraform (placeholder)

Terraform for the jhuk.tech static-site infrastructure. Added in a later phase.

Planned (all `us-east-1`, all code-managed):

- Private S3 content bucket (no public access, no S3 website hosting).
- CloudFront distribution reading the bucket via Origin Access Control (OAC).
- ACM certificate (DNS-validated via a CNAME added manually at Namecheap).
- GitHub OIDC provider + least-privilege CI deploy role
  (S3 read/write on the content bucket + `cloudfront:CreateInvalidation` on the
  one distribution — nothing more).

Remote state lives in the existing bucket `jhuk-tech-tfstate-877995959706`
(versioned, S3 native locking). One concern per file: `s3.tf`, `cloudfront.tf`,
`acm.tf`, `iam_oidc.tf`, `outputs.tf`, `variables.tf`.

> Applies are run by the maintainer only. Claude runs `terraform plan` only.
