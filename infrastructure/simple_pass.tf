# =============================================================================
# SIMPLE_PASS.TF — Minimal single-resource file: all policies satisfied
# Expected: adag scan simple_pass.tf → EXIT 0, 0 violations
#
# Deliberately simple to minimise LLM ambiguity:
#   ✓ delete_protection          ✓ encryption_at_rest
#   ✓ backup_retention           ✓ automated_backups_enabled
#   ✓ multi_az_requirement       ✓ public_access_block
#   ✓ required_tagging           ✓ naming_conventions
#   ✓ allowed_regions
# =============================================================================

provider "aws" {
  region = "us-east-1" # ✓ allowed_regions
}

resource "aws_db_instance" "prod-api-db-simple" {
  identifier        = "prod-api-db-simple" # ✓ naming_conventions (lowercase, hyphens)
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.medium"
  allocated_storage = 20

  storage_encrypted   = true # ✓ encryption_at_rest
  deletion_protection = true # ✓ delete_protection

  backup_retention_period = 7 # ✓ backup_retention + automated_backups_enabled
  backup_window           = "02:00-03:00"

  multi_az            = true  # ✓ multi_az_requirement
  publicly_accessible = false # ✓ public_access_block

  skip_final_snapshot       = false
  final_snapshot_identifier = "prod-api-db-simple-final"

  tags = {
    Environment = "production" # ✓ required_tagging
    Owner       = "infra-team@example.com"
    Application = "api"
    CostCenter  = "CC-100"
  }
}
