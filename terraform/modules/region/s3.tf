# Bucket name suffix — S3 bucket names are globally unique, same
# pattern as the state bucket in terraform/bootstrap.
resource "random_id" "assets_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-${local.role}-${var.assets_bucket_prefix}-${random_id.assets_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-assets"
  })
}

# CRR requires versioning on BOTH source and destination buckets —
# not just the source.
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Replication (source/primary side only) ---
# Apply order: this only activates once replication_destination_bucket_arn
# is set, so primary's FIRST apply (before secondary exists) just creates
# the bucket — safe to run before secondary. Re-apply primary a second
# time, after secondary exists and its ARN is filled in, to attach
# the actual replication config.

data "aws_iam_policy_document" "replication_assume_role" {
  count = var.is_primary && var.replication_destination_bucket_arn != null ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count = var.is_primary && var.replication_destination_bucket_arn != null ? 1 : 0

  name               = "${var.project_name}-${local.role}-s3-replication-role"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role[0].json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${local.role}-s3-replication-role"
  })
}

data "aws_iam_policy_document" "replication" {
  count = var.is_primary && var.replication_destination_bucket_arn != null ? 1 : 0

  statement {
    sid       = "SourceBucketRead"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.assets.arn]
  }

  statement {
    sid = "SourceObjectRead"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }

  statement {
    sid = "DestinationWrite"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${var.replication_destination_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  count = var.is_primary && var.replication_destination_bucket_arn != null ? 1 : 0

  name   = "${var.project_name}-${local.role}-s3-replication-policy"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "assets" {
  count = var.is_primary && var.replication_destination_bucket_arn != null ? 1 : 0

  # Versioning must be enabled before a replication config can attach.
  depends_on = [aws_s3_bucket_versioning.assets]

  bucket = aws_s3_bucket.assets.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    filter {} # no prefix filter — replicate everything in the bucket

    delete_marker_replication {
      status = "Disabled" # explicit — newer S3 CRR schema requires this block
    }

    destination {
      bucket        = var.replication_destination_bucket_arn
      storage_class = "STANDARD"
    }
  }
}
