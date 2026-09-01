terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "Region the state bucket + lock table live in (pick one, doesn't need to match app regions)"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Used to name the bucket/table — must match project_name in the main config"
  type        = string
  default     = "multi-region-dr"
}

# Bucket name must be globally unique. Account ID gives a deterministic,
# collision-safe suffix — unlike a random one, it's stable across
# destroy/recreate cycles, so backend.tf's hardcoded bucket name never
# goes stale just because bootstrap was torn down and rebuilt.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket        = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  # Bootstrap resource, not part of the app — safe to leave protected
  # even though everything else in this project gets destroyed between
  # sessions. State history matters more than the cost of one small bucket.
  # (Removed manually for a one-off full teardown on 2026-08-23 — restore
  # this if that's not routine going forward.)
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.lock.name
}
