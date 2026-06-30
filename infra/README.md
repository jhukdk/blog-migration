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
  custom domain `jhuk.tech` (+ `www.jhuk.tech`) with the ACM cert attached, so the
  www→apex 301 is live.
- **WAFv2 web ACL** (`waf.tf`) — `CLOUDFRONT`-scoped, default action `allow`,
  attached to the distribution by ARN. Three rules: a demo header-match block, the
  AWS-managed `CommonRuleSet`, and a per-IP rate limit (`var.waf_rate_limit` over a
  5-minute window). Blocks surface as 403 (see the CloudFront 403 note above). Logs
  to a CloudWatch log group (30-day retention).
- **ACM certificate** (`acm.tf`) — DNS-validated cert for `jhuk.tech` +
  `www.jhuk.tech`, validated via a CNAME added manually at Namecheap and attached
  to the distribution. Terraform outputs the validation records; it does not create
  them in DNS.
- **GitHub OIDC + deploy role** (`iam_oidc.tf`) — keyless CI auth. The role is
  assumable only by the configured repo/branch and is scoped to read/write on the
  content bucket plus `cloudfront:CreateInvalidation` on the one distribution.

## Files
`versions.tf` (providers + S3 backend), `providers.tf`, `variables.tf`,
`locals.tf` (account-derived bucket names), `s3.tf`, `cloudfront.tf`,
`functions/rewrite_index.js`, `waf.tf`, `acm.tf`, `iam_oidc.tf`, `outputs.tf`.

The AWS account ID is never hardcoded. Deterministic bucket names are derived at
runtime from `data.aws_caller_identity.current.account_id` (see `locals.tf`), and
the state-bucket name is supplied through partial backend config (below).

## State backend
Remote state lives in the pre-existing bucket `jhuk-tech-tfstate-<accountid>`
(key `jhuk/terraform.tfstate`, native S3 locking via `use_lockfile`). The bucket is
created manually and is **not** managed by this code. Its name carries the account
ID, so it is kept out of source: `versions.tf` omits `bucket` and you pass it via
partial backend config. Copy the template and fill in your account ID:
```sh
cp backend.hcl.example backend.hcl   # backend.hcl is gitignored
# edit backend.hcl -> bucket = "jhuk-tech-tfstate-<your-account-id>"
```

## Usage
```sh
terraform init -backend-config=backend.hcl   # configures the S3 backend
terraform plan                               # review — the maintainer applies, not Claude
terraform apply                              # maintainer only
```
For the certificate, read `terraform output acm_validation_records` and add the
CNAME(s) at Namecheap; ACM then reports the cert `ISSUED` and CloudFront attaches it.

## Notes / caveats
- **One OIDC provider per account.** An AWS account can have only one IAM OIDC
  provider for `token.actions.githubusercontent.com`. If one already exists, import
  it before apply to avoid `EntityAlreadyExists`:
  `terraform import aws_iam_openid_connect_provider.github arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`
- The cert is validated by the Namecheap CNAME and attached to the distribution;
  the site serves on the custom domain `jhuk.tech`. The
  `aws_acm_certificate_validation` resource gates attachment on ACM reporting
  `ISSUED`, so a missing/withdrawn CNAME would block the apply rather than fail open.
- Provider pinned to `hashicorp/aws ~> 6.50`; Terraform `>= 1.10` (for `use_lockfile`).

## Hard rules
Per repo `CLAUDE.md`: this code is plan-reviewed only — **applies are run by the
maintainer**. No DNS records, no public bucket, least-privilege CI role.
