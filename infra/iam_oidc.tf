# GitHub Actions OIDC identity provider. thumbprint_list is intentionally omitted:
# AWS no longer requires it for this provider (it secures the endpoint itself), and
# the AWS provider treats it as optional.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Trust policy: only GitHub Actions runs matching github_oidc_subjects (default:
# the main branch of the repo) may assume this role, and only with the AWS audience.
data "aws_iam_policy_document" "deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_oidc_subjects
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "jhuk-tech-ci-deploy"
  description        = "GitHub Actions role to deploy the jhuk.tech static site"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
}

# Least privilege: sync content to the one bucket and invalidate the one
# distribution. Nothing else.
data "aws_iam_policy_document" "deploy_permissions" {
  statement {
    sid       = "ListContentBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.content.arn]
  }

  statement {
    sid       = "ReadWriteContentObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.content.arn}/*"]
  }

  statement {
    sid       = "InvalidateDistribution"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.this.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "jhuk-tech-ci-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}
