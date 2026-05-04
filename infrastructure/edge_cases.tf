# =============================================================================
# EDGE_CASES.TF — Tricky scenarios the agent must handle correctly
# Expected: adag scan edge_cases.tf → violations on cases 2, 3, 4 only
#
# Case 1: Attribute entirely absent (not false, just missing) → VIOLATION
# Case 2: deletion_protection = false explicitly → VIOLATION
# Case 3: backup_retention_period = 0 explicitly → VIOLATION
# Case 4: Non-database resource (aws_lambda_function) → should be IGNORED
#         (no RDS policies apply to it)
# Case 5: Read replica — backup_retention_period = 0 is acceptable
#         (primary has backups, replica is derived)
# =============================================================================

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# EDGE CASE 1: deletion_protection completely absent (no attribute at all)
# AWS default is false — agent must flag this as a violation
# -----------------------------------------------------------------------------
resource "aws_db_instance" "prod-api-db-no-protection-attr" {
  identifier        = "prod-api-db-no-protection-attr"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted = true
  # deletion_protection is entirely missing — should be flagged ✗

  backup_retention_period = 14
  backup_window           = "03:00-04:00"

  multi_az            = true
  publicly_accessible = false

  skip_final_snapshot = true

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

# -----------------------------------------------------------------------------
# EDGE CASE 2: deletion_protection = false explicitly
# Should be flagged ✗
# -----------------------------------------------------------------------------
resource "aws_db_instance" "prod-api-db-explicit-false" {
  identifier        = "prod-api-db-explicit-false"
  engine            = "postgres"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = false # ✗ explicit false

  backup_retention_period = 14
  backup_window           = "03:00-04:00"

  multi_az            = true
  publicly_accessible = false

  skip_final_snapshot = true

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

# -----------------------------------------------------------------------------
# EDGE CASE 3: backup_retention_period = 0 (disables automated backups)
# Should flag both backup_retention and automated_backups_enabled ✗
# -----------------------------------------------------------------------------
resource "aws_db_instance" "prod-api-db-no-backups" {
  identifier        = "prod-api-db-no-backups"
  engine            = "postgres"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = true

  backup_retention_period = 0 # ✗ disables all automated backups

  multi_az            = true
  publicly_accessible = false

  skip_final_snapshot = true

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

# -----------------------------------------------------------------------------
# EDGE CASE 4: Non-database resource — Lambda function
# RDS/database policies (delete_protection, backup, multi_az) should NOT apply
# Only tag and naming policies apply
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "prod-api-processor-fn" {
  function_name = "prod-api-processor-fn"
  role          = "arn:aws:iam::123456789012:role/lambda-role"
  handler       = "index.handler"
  runtime       = "python3.11"

  filename         = "function.zip"
  source_code_hash = filebase64sha256("function.zip")

  tags = {
    Environment = "production"
    Owner       = "backend-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

# -----------------------------------------------------------------------------
# EDGE CASE 5: Read replica with backup_retention_period = 0
# This is an acceptable exception — replica derives from primary
# Agent should ideally note it's a replica and treat leniently
# -----------------------------------------------------------------------------
resource "aws_db_instance" "prod-api-db-replica" {
  identifier          = "prod-api-db-replica"
  replicate_source_db = aws_db_instance.prod-api-db-no-protection-attr.identifier
  instance_class      = "db.r5.large"

  deletion_protection = true
  publicly_accessible = false

  backup_retention_period = 0 # Acceptable for replica — primary has backups

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
    Role        = "read-replica"
    BackupNote  = "Primary instance has backups enabled"
  }
}
