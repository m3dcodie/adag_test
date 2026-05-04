# =============================================================================
# MIXED.TF — Some resources compliant, some not
# Expected: adag scan mixed.tf → EXIT 1, violations on bad_* resources only
#
# Tests that the agent reports at resource-level, not file-level.
# good_db     → should PASS (0 violations)
# bad_db      → should FAIL (delete_protection, encryption, backup, multi_az, tags)
# good_kms    → should PASS
# bad_kms     → should FAIL (kms_key_rotation)
# =============================================================================

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# COMPLIANT: good_db satisfies all policies
# -----------------------------------------------------------------------------
resource "aws_db_instance" "prod-api-db-good" {
  identifier        = "prod-api-db-good"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = true

  backup_retention_period = 14
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  multi_az            = true
  publicly_accessible = false

  skip_final_snapshot       = false
  final_snapshot_identifier = "prod-api-db-good-final"

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# VIOLATION: bad_db — missing delete protection, no encryption, no backups,
#            single-AZ, publicly accessible, missing tags
# -----------------------------------------------------------------------------
resource "aws_db_instance" "dev_db_unprotected" { # ✗ naming_conventions
  identifier        = "dev_db_unprotected"        # ✗ naming_conventions (underscore)
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  storage_encrypted   = false # ✗ encryption_at_rest
  deletion_protection = false # ✗ delete_protection

  backup_retention_period = 0 # ✗ backup_retention + automated_backups_enabled

  multi_az            = false # ✗ multi_az_requirement (tagged production)
  publicly_accessible = true  # ✗ public_access_block

  skip_final_snapshot = true

  tags = {
    Environment = "production" # Production but none of the other required tags
    # ✗ required_tagging — missing Owner, Application, CostCenter
  }
}

# -----------------------------------------------------------------------------
# COMPLIANT: good KMS key — rotation enabled
# -----------------------------------------------------------------------------
resource "aws_kms_key" "prod-api-kms-primary" {
  description             = "KMS key for production API encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true # ✓ kms_key_rotation

  tags = {
    Environment = "production"
    Owner       = "security-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# VIOLATION: bad KMS key — rotation disabled, bad name, missing tags
# -----------------------------------------------------------------------------
resource "aws_kms_key" "Legacy_Key_NoRotation" { # ✗ naming_conventions
  description             = "Old key, rotation forgotten"
  deletion_window_in_days = 7
  enable_key_rotation     = false # ✗ kms_key_rotation

  tags = {
    # ✗ required_tagging — missing all required tags
    Notes = "legacy"
  }
}
