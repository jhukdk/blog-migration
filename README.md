# From WordPress Cpanel → AWS Cloudfront and S3

This project documents migration of my personal WordPress blog at [jhuk.tech](https://jhuk.tech) to 
a [Hugo](https://gohugo.io) static site hosted on **AWS S3 + CloudFront**, provisioned with 
**Terraform** and deployed by **GitHub Actions**. All infrastructure is code; all content is Markdown.

## Architecture

```
Markdown (site/content) ──hugo build──▶ static HTML
                                          │
                          GitHub Actions (OIDC, no stored keys)
                                          │
                         S3 sync ──▶ private S3 bucket ──OAC──▶ CloudFront ──▶ WAFv2 ──▶ viewers
```

- **Hugo static site** — source in [`/site`](site); posts are Markdown with front
  matter. Theme is [Congo](https://github.com/jpanther/congo) installed via Hugo Modules.
- **Terraform** — [`/infra`](infra) provisions a private S3 content bucket, CloudFront
  (Origin Access Control) with a viewer-request function (www→apex 301 redirect +
  pretty-URL rewrite), a WAFv2 web ACL on the distribution, an ACM certificate, the
  GitHub OIDC provider, and a least-privilege CI deploy role. Remote state lives in a
  pre-existing S3 bucket.
- **CI/CD** — [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml): on push to
  `main` touching `site/**`, build Hugo and deploy (S3 sync + CloudFront invalidation)
  via GitHub OIDC — no stored AWS keys.
- **DNS** stays at Namecheap and now points at CloudFront (cutover complete). The ACM
  certificate is validated by a CNAME added manually at Namecheap; Route 53 is not used.

Everything runs in **us-east-1** (required for the CloudFront ACM certificate and
the `CLOUDFRONT`-scoped WAFv2 web ACL).

## Edge security — WAFv2

A [WAFv2](https://docs.aws.amazon.com/waf/latest/developerguide/) web ACL is
attached to the CloudFront distribution (`web_acl_id`), inspecting every
viewer request at the edge before it reaches the origin. It is `CLOUDFRONT`-scoped,
so — like the ACM certificate — it must live in **us-east-1**. The default action
is **allow**; only the rules below block. All of it is Terraform in
[`infra/waf.tf`](infra/waf.tf).

| Priority | Rule | Action | Purpose |
|---|---|---|---|
| 0 | `DemoBlockByHeader` | Block | Blocks any request carrying the configured demo header (`curl -H "x-demo-block: blocked" https://jhuk.tech/` → `403`) — an on-demand way to demonstrate a WAF block. |
| 1 | `AWSManagedRulesCommonRuleSet` | Managed | AWS-managed baseline protections against common exploit patterns and bad inputs; each managed rule keeps its own action. |
| 2 | `RateLimitPerIP` | Block | Rate-based rule that blocks any single source IP exceeding the configured threshold within a 5-minute window. |

The demo header name/value and the rate-limit threshold are Terraform variables
(`waf_demo_block_header_name`, `waf_demo_block_header_value`, `waf_rate_limit`).
Logging is enabled to a CloudWatch log group (`aws-waf-logs-jhuk-tech-cloudfront`,
30-day retention), and CloudWatch metrics plus sampled requests are on for the web
ACL and each rule.

## Repository layout

| Path | Contents |
|---|---|
| [`site/`](site) | Hugo site — content, config (split layout in `config/_default/`), theme module |
| [`infra/`](infra) | Terraform — `s3.tf`, `cloudfront.tf`, `waf.tf`, `acm.tf`, `iam_oidc.tf`, etc. ([details](infra/README.md)) |
| [`.github/workflows/`](.github/workflows) | GitHub Actions deploy pipeline ([details](.github/workflows/README.md)) |
| `migration-source/` | Exported WordPress content used as the migration source |
| `scripts/` | Helper scripts for the migration |

## Local development

```sh
cd site
hugo server          # live-reload preview at http://localhost:1313
hugo --minify --gc   # production build into site/public
```

Hugo **extended** and **Go** are required (Congo is pulled in as a Hugo Module).

## Infrastructure

```sh
cd infra
terraform init       # configures the S3 backend
terraform plan       # review changes
terraform apply      # maintainer only
```

After the first apply, read `terraform output acm_validation_records` and add the
CNAME(s) at Namecheap to validate the certificate. See [`infra/README.md`](infra/README.md)
for state backend details and caveats (e.g. the single-per-account OIDC provider).

## Deployment

Pushing to `main` with changes under `site/**` triggers
[`deploy.yml`](.github/workflows/deploy.yml), which builds the site and deploys it
keylessly via GitHub OIDC. Three non-secret repository **Variables** wire it up —
`DEPLOY_ROLE_ARN`, `CONTENT_BUCKET`, and `DISTRIBUTION_ID`, each sourced from a
`terraform output`. See the [workflow README](.github/workflows/README.md).

## Conventions & guardrails

- Permalinks are preserved exactly as `/:year/:month/:day/:slug/` — SEO depends on it.
- `www.jhuk.tech` 301-redirects to the apex `https://jhuk.tech` at the edge. That
  redirect and the pretty-URL→`index.html` rewrite share one CloudFront
  viewer-request function (only one may bind per event type).
- The S3 content bucket stays **private**; CloudFront reads it via OAC only.
- The CI IAM role is least-privilege: read/write on the content bucket and
  `cloudfront:CreateInvalidation` on the one distribution.
- Terraform applies and all DNS changes are performed by the maintainer.
- Work happens on branches via pull requests; no direct pushes to `main`.

See [`CLAUDE.md`](CLAUDE.md) for the full set of project rules and conventions.
