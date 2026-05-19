# test_cases/rds_compliant/main.tf
# Expected: PASS — all 10 policies satisfied
# Isolated RDS instance that satisfies every policy in policies/.

provider "aws" {
  region = "us-east-1" # ✓ allowed_regions
}

resource "aws_kms_key" "rds-encryption-key" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true # ✓ kms_key_rotation

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

resource "aws_db_instance" "prod-api-db-primary" {
  identifier        = "prod-api-db-primary" # ✓ naming_conventions (lowercase, hyphens)
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true # ✓ encryption_at_rest
  kms_key_id          = aws_kms_key.rds-encryption-key.arn
  deletion_protection = true # ✓ delete_protection

  backup_retention_period = 14 # ✓ backup_retention + automated_backups_enabled
  backup_window           = "03:00-04:00"

  multi_az                  = true  # ✓ multi_az_requirement
  publicly_accessible       = false # ✓ public_access_block
  skip_final_snapshot       = false
  final_snapshot_identifier = "prod-api-db-primary-final"

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}
