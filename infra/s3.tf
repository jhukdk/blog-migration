# Private S3 bucket holding the built Hugo site. It is NEVER public: CloudFront
# reads it through Origin Access Control (OAC) only. No website hosting.
resource "aws_s3_bucket" "content" {
  bucket = var.content_bucket_name
}

# Block every avenue of public access.
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs entirely; the bucket owner owns every object.
resource "aws_s3_bucket_ownership_controls" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Keep prior versions so a bad deploy can be rolled back.
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt objects at rest with S3-managed keys.
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Allow only this CloudFront distribution (via OAC) to read objects. The
# SourceArn condition scopes access to the one distribution; nothing else can read.
data "aws_iam_policy_document" "content" {
  statement {
    sid     = "AllowCloudFrontOACRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.content.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id
  policy = data.aws_iam_policy_document.content.json

  # Ensure public access is locked down before any policy is attached.
  depends_on = [aws_s3_bucket_public_access_block.content]
}
