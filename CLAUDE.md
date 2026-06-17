# jhuk.tech — WordPress → AWS static-site migration

Migrates the WordPress blog at jhuk.tech to a Hugo static site hosted on
AWS S3 + CloudFront, provisioned with Terraform, deployed by GitHub Actions.
All infrastructure is code; all content is Markdown.

## Architecture
- Hugo static site. Source in `/site`; posts are Markdown with front matter.
- `/infra`: Terraform for a private S3 content bucket, CloudFront (Origin
  Access Control) with a viewer-request function (www→apex 301 redirect +
  pretty-URL→index.html rewrite), a WAFv2 web ACL on the distribution, ACM
  certificate, GitHub OIDC provider, and a least-privilege CI deploy role.
  Remote state in an existing S3 bucket.
- `/.github/workflows`: on push to main, build Hugo and deploy content
  (S3 sync + CloudFront invalidation) via GitHub OIDC — no stored AWS keys.
- DNS stays at Namecheap through cutover. ACM is validated by a CNAME I add
  manually at Namecheap. Route 53 is NOT used in this phase.

## Region
- Everything is us-east-1. The ACM cert for CloudFront and the distribution
  must be there; keep the content bucket there too for simplicity.

## Hard rules — never break these
- NEVER run `terraform apply`/`destroy` or any state-changing `aws` CLI
  command. Write code and run `terraform plan` only. I run all applies.
- NEVER create, modify, or delete AWS resources outside Terraform.
- NEVER touch DNS records or nameservers. I handle all DNS manually.
- The S3 content bucket stays PRIVATE; CloudFront reads it via OAC only.
  Never enable public access or S3 static-website hosting.
- Preserve permalinks EXACTLY: `/:year/:month/:day/:slug/`. SEO depends on it.
- `www.jhuk.tech` 301-redirects to the apex `jhuk.tech` for one canonical host.
  That redirect AND the pretty-URL→`index.html` rewrite both live in the single
  CloudFront viewer-request function `infra/functions/rewrite_index.js`; only one
  function can bind per event type, so keep both concerns in that one file.
- Scope the CI IAM role to least privilege: read/write on the content bucket
  and cloudfront:CreateInvalidation on the one distribution. Nothing more.
- NEVER commit secrets or state. `.gitignore` must cover *.tfstate*,
  *.tfvars, .terraform/, .aws/, and any .env or credential files.
- Don't push to main directly. Work on a branch; open a PR.

## Conventions
- Small, focused commits. Pin Terraform provider versions; run `terraform fmt`.
- One concern per Terraform file (s3.tf, cloudfront.tf, waf.tf, acm.tf,
  iam_oidc.tf, outputs.tf, variables.tf). CloudFront function code lives under
  infra/functions/, not inline in HCL.
- When unsure of an AWS provider argument, check current docs, don't guess.

## State backend (I create this bucket manually; do not create it in code)
- Bucket: jhuk-tech-tfstate-877995959706 (us-east-1), versioning on,
  S3 native locking (use_lockfile = true).

  ## Hugo + Congo theme
- The Hugo site lives in /site. Theme is Congo (jpanther/congo/v2), installed
  via Hugo Modules — NOT a submodule, NOT manual.
- Config uses the split layout in /site/config/_default/: hugo.toml, params.toml,
  markup.toml, menus.en.toml, languages.en.toml, module.toml. There is NO
  hugo.toml in the site root — delete the one `hugo new site` generates.
- module.toml imports path "github.com/jpanther/congo/v2". Because we use Hugo
  Modules, do NOT add `theme = "congo"` anywhere.
- NEVER delete or empty markup.toml — Congo requires its goldmark/highlight
  settings to render correctly.
- Posts live in /site/content/posts/. Set mainSections = ["posts"].
- Permalinks go in config/_default/hugo.toml as:
  [permalinks]
    posts = "/:year/:month/:day/:slug/"
- Front matter must stay Congo-compatible (title, date, slug, tags, categories,
  draft). Preserve each post's original slug exactly.