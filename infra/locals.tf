# Account ID is resolved at runtime (never hardcoded) so it stays out of source
# control. The deterministic bucket names are derived from it, matching the names
# created out-of-band. An explicit var override still wins if ever needed.
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  content_bucket_name = coalesce(
    var.content_bucket_name,
    "jhuk-tech-content-${local.account_id}",
  )

  cf_logs_bucket_name = coalesce(
    var.cf_logs_bucket_name,
    "jhuk-tech-cf-logs-${local.account_id}",
  )
}
