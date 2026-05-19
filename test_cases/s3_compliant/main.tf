# test_cases/s3_compliant/main.tf
# Expected: PASS — all applicable policies satisfied
# S3 bucket with encryption, public access block, and required tags.

provider "aws" {
  region = "us-east-1" # ✓ allowed_regions
}

resource "aws_kms_key" "s3-encryption-key" {
  description             = "KMS key for S3 server-side encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true # ✓ kms_key_rotation

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

resource "aws_s3_bucket" "app-data-store" {
  bucket = "app-data-store-prod" # ✓ naming_conventions (lowercase, hyphens)

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app-data-store" {
  bucket = aws_s3_bucket.app-data-store.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms" # ✓ encryption_at_rest
      kms_master_key_id = aws_kms_key.s3-encryption-key.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app-data-store" {
  bucket = aws_s3_bucket.app-data-store.id

  block_public_acls       = true # ✓ public_access_block
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
