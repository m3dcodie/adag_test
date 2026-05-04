# per_policy/no_backup.tf
# Expected: violations — backup_retention + automated_backups_enabled
resource "aws_db_instance" "prod-api-db-primary" {
  identifier        = "prod-api-db-primary"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = true

  backup_retention_period = 0 # ✗ VIOLATION — disables automated backups
  # backup_window intentionally absent

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
