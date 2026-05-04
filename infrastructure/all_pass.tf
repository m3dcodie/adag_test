# =============================================================================
# ALL_PASS.TF — Every resource satisfies all 10 ADAG policies
# Expected: adag scan all_pass.tf → EXIT 0, 0 violations
#
# Policies covered (all compliant):
#   ✓ delete_protection          ✓ encryption_at_rest
#   ✓ backup_retention           ✓ automated_backups_enabled
#   ✓ multi_az_requirement       ✓ public_access_block
#   ✓ required_tagging           ✓ naming_conventions
#   ✓ allowed_regions            ✓ kms_key_rotation
# =============================================================================

# Allowed region (us-east-1 is in approved list)
provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# KMS Key — rotation enabled
# -----------------------------------------------------------------------------
resource "aws_kms_key" "prod_db_key" {
  description             = "KMS key for production database encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true # ✓ kms_key_rotation

  tags = {
    Name        = "prod-db-key" # ✓ naming_conventions (Name tag)
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# RDS Instance — all policies satisfied
# -----------------------------------------------------------------------------
resource "aws_db_instance" "prod-api-db-primary" {
  identifier        = "prod-api-db-primary" # ✓ naming_conventions
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100
  storage_type      = "gp3"

  storage_encrypted = true # ✓ encryption_at_rest
  kms_key_id        = aws_kms_key.prod_db_key.arn

  username = "admin"
  password = "ReplaceWithSecretsManager!"

  deletion_protection = true # ✓ delete_protection

  backup_retention_period = 14 # ✓ backup_retention + automated_backups_enabled
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  multi_az            = true  # ✓ multi_az_requirement
  publicly_accessible = false # ✓ public_access_block

  skip_final_snapshot       = false
  final_snapshot_identifier = "prod-api-db-primary-final"

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Aurora Cluster — all policies satisfied
# -----------------------------------------------------------------------------
resource "aws_rds_cluster" "prod-orders-aurora-cluster" {
  cluster_identifier = "prod-orders-aurora-cluster" # ✓ naming_conventions
  engine             = "aurora-postgresql"
  engine_version     = "15.2"
  database_name      = "ordersdb"
  master_username    = "admin"
  master_password    = "ReplaceWithSecretsManager!"

  storage_encrypted = true # ✓ encryption_at_rest
  kms_key_id        = aws_kms_key.prod_db_key.arn

  deletion_protection = true # ✓ delete_protection

  backup_retention_period      = 14 # ✓ backup_retention + automated_backups_enabled
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "prod-orders-aurora-cluster-final"

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "orders-team@company.com"
    Application = "orders-service"
    CostCenter  = "CC-1002"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket + Public Access Block — all policies satisfied
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "prod-api-data-bucket" {
  bucket = "prod-api-data-bucket" # ✓ naming_conventions

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "prod-api-data-bucket" {
  bucket = aws_s3_bucket.prod-api-data-bucket.id

  block_public_acls       = true # ✓ public_access_block
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prod-api-data-bucket" {
  bucket = aws_s3_bucket.prod-api-data-bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms" # ✓ encryption_at_rest
      kms_master_key_id = aws_kms_key.prod_db_key.arn
    }
  }
}
