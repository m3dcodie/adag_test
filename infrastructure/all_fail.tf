# =============================================================================
# ALL_FAIL.TF — Every resource violates all 10 ADAG policies
# Expected: adag scan all_fail.tf → EXIT 1, maximum violations
#
# Policies violated:
#   ✗ delete_protection          ✗ encryption_at_rest
#   ✗ backup_retention           ✗ automated_backups_enabled
#   ✗ multi_az_requirement       ✗ public_access_block
#   ✗ required_tagging           ✗ naming_conventions
#   ✗ allowed_regions            ✗ kms_key_rotation
# =============================================================================

# VIOLATION: allowed_regions — ap-southeast-3 is not in the approved list
provider "aws" {
  region = "ap-southeast-3"
}

# -----------------------------------------------------------------------------
# KMS Key — rotation disabled
# -----------------------------------------------------------------------------
resource "aws_kms_key" "BadKey_NoRotation" { # ✗ naming_conventions (underscores, uppercase)
  description             = "KMS key without rotation"
  deletion_window_in_days = 7
  enable_key_rotation     = false # ✗ kms_key_rotation

  tags = {
    # ✗ required_tagging — missing Environment, Owner, Application, CostCenter
    Name = "bad-key"
  }
}

# -----------------------------------------------------------------------------
# RDS Instance — all policies violated
# -----------------------------------------------------------------------------
resource "aws_db_instance" "BadDB_Unprotected" {
  identifier        = "BadDB_Unprotected" # ✗ naming_conventions (uppercase, underscores)
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  storage_encrypted = false # ✗ encryption_at_rest

  username = "root"
  password = "password123"

  deletion_protection = false # ✗ delete_protection

  backup_retention_period = 0 # ✗ backup_retention + automated_backups_enabled
  # ✗ backup_window not defined

  multi_az            = false # ✗ multi_az_requirement
  publicly_accessible = true  # ✗ public_access_block

  skip_final_snapshot = true

  tags = {
    # ✗ required_tagging — missing Owner, Application, CostCenter
    Name = "bad-database"
  }
}

# -----------------------------------------------------------------------------
# Aurora Cluster — all policies violated
# -----------------------------------------------------------------------------
resource "aws_rds_cluster" "BadAurora_NoProtection" {
  cluster_identifier = "BadAurora_NoProtection" # ✗ naming_conventions
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.02.0"
  database_name      = "baddb"
  master_username    = "root"
  master_password    = "password456"

  storage_encrypted = false # ✗ encryption_at_rest

  deletion_protection = false # ✗ delete_protection

  backup_retention_period = 0 # ✗ backup_retention + automated_backups_enabled
  # ✗ preferred_backup_window not defined

  skip_final_snapshot = true

  tags = {
    # ✗ required_tagging — missing Owner, Application, CostCenter
    Environment = "production"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket — no public access block, no encryption, bad naming
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "MyBucket_Public" {
  bucket = "MyBucket_Public" # ✗ naming_conventions (uppercase, underscores)

  tags = {
    # ✗ required_tagging — missing all required tags
    Team = "random"
  }
}

# No aws_s3_bucket_public_access_block → ✗ public_access_block
# No aws_s3_bucket_server_side_encryption_configuration → ✗ encryption_at_rest
