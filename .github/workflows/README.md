# .github/workflows — CI/CD (placeholder)

GitHub Actions workflows for jhuk.tech. Added in a later phase.

Planned: on push to `main`, build the Hugo site (`/site`) and deploy content via
GitHub OIDC (no stored AWS keys):

1. Checkout + set up Hugo (extended) and Go (for Hugo Modules).
2. `hugo --gc --minify` to build `/site/public`.
3. Assume the least-privilege deploy role via OIDC.
4. `aws s3 sync` to the private content bucket.
5. `aws cloudfront create-invalidation` on the single distribution.
