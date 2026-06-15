# .github/workflows — CI/CD

## `deploy.yml`
On push to `main` that touches `site/**` (or via manual `workflow_dispatch`):

1. Checkout, set up Go (Congo is a Hugo Module) and Hugo extended.
2. `hugo --minify --gc` in `/site` (builds with the production `https://jhuk.tech/`
   baseURL from the committed config).
3. Authenticate to AWS via **GitHub OIDC** — assumes the deploy role; no stored keys.
4. `aws s3 sync ./site/public s3://<bucket> --delete`.
5. `aws cloudfront create-invalidation --paths "/*"` on the distribution.

### Required repository variables (Settings → Secrets and variables → Actions → Variables)
| Variable | Value | Source |
|---|---|---|
| `DEPLOY_ROLE_ARN` | OIDC deploy role ARN | `terraform output deploy_role_arn` |
| `CONTENT_BUCKET` | content bucket name | `terraform output content_bucket_name` |
| `DISTRIBUTION_ID` | CloudFront distribution ID | `terraform output cloudfront_distribution_id` |

These are non-secret **Variables** (not Secrets). The role's trust policy already
restricts assumption to this repo's `main` branch, so no AWS keys are ever stored.
