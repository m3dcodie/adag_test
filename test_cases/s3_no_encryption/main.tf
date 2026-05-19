# test_cases/s3_no_encryption/main.tf
# Expected: FAIL — encryption_at_rest policy
# S3 bucket exists but has no server-side encryption configuration.
# aws_s3_bucket_public_access_block is present so public_access_block is satisfied.

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "app-data-store" {
  bucket = "app-data-store-prod"

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

resource "aws_s3_bucket_public_access_block" "app-data-store" {
  bucket = aws_s3_bucket.app-data-store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ✗ VIOLATION — no aws_s3_bucket_server_side_encryption_configuration
# encryption_at_rest policy requires server-side encryption on all S3 buckets
