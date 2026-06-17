# infra — Terraform for jhuk.tech

Infrastructure as code for the jhuk.tech static site. Everything is `us-east-1`.

## What this provisions
- **S3 content bucket** (`s3.tf`) — private, no public access, no website hosting,
  versioned, SSE-S3. Readable only by CloudFront via Origin Access Control (OAC),
  which is granted `s3:GetObject` plus `s3:ListBucket` so missing keys return a
  true 404 rather than 403.
- **CloudFront** (`cloudfront.tf`) — OAC origin to the bucket, `default_root_object`
  `index.html`, 404 → `/404.html` (404) — 403 is left untouched so WAF/forbidden
  responses surface as 403 — and a viewer-request **CloudFront
  Function** (`functions/rewrite_index.js`) that (1) 301-redirects `www.jhuk.tech`
  to the apex `https://jhuk.tech` for canonicalization, then (2) appends
  `index.html` to directory paths so Hugo pretty URLs resolve. Serves on the
  default `*.cloudfront.net` domain (no custom alias/cert attached yet).
- **ACM certificate** (`acm.tf`) — DNS-validated cert for `jhuk.tech` +
  `www.jhuk.tech`. Validation records are **output only**; add them at Namecheap.
- **GitHub OIDC + deploy role** (`iam_oidc.tf`) — keyless CI auth. The role is
  assumable only by the configured repo/branch and is scoped to read/write on the
  content bucket plus `cloudfront:CreateInvalidation` on the one distribution.

## Files
`versions.tf` (providers + S3 backend), `providers.tf`, `variables.tf`, `s3.tf`,
`cloudfront.tf`, `functions/rewrite_index.js`, `acm.tf`, `iam_oidc.tf`, `outputs.tf`.

## State backend
Remote state in the pre-existing bucket `jhuk-tech-tfstate-877995959706`
(key `jhuk/terraform.tfstate`, native S3 locking via `use_lockfile`). The bucket is
created manually and is **not** managed by this code.

## Usage
```sh
terraform init                 # configures the S3 backend
terraform plan                 # review — the maintainer applies, not Claude
terraform apply                # maintainer only
```
After apply, read `terraform output acm_validation_records` and add the CNAME(s) at
Namecheap to validate the certificate.

## Notes / caveats
- **One OIDC provider per account.** An AWS account can have only one IAM OIDC
  provider for `token.actions.githubusercontent.com`. If one already exists, import
  it before apply to avoid `EntityAlreadyExists`:
  `terraform import aws_iam_openid_connect_provider.github arn:aws:iam::877995959706:oidc-provider/token.actions.githubusercontent.com`
- The certificate stays `PENDING_VALIDATION` until the Namecheap CNAME is added.
  That does not block serving on the CloudFront default domain.
- Provider pinned to `hashicorp/aws ~> 6.50`; Terraform `>= 1.10` (for `use_lockfile`).

## Hard rules
Per repo `CLAUDE.md`: this code is plan-reviewed only — **applies are run by the
maintainer**. No DNS records, no public bucket, least-privilege CI role.
