# per_policy/no_auto_backup.tf
# Expected: 1 violation — automated_backups_enabled
# backup_retention_period is > 0 but backup_window is missing
# (AWS will pick a random window — policy requires explicit window)
resource "aws_rds_cluster" "prod-orders-aurora-cluster" {
  cluster_identifier = "prod-orders-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_version     = "15.2"
  database_name      = "ordersdb"
  master_username    = "admin"
  master_password    = "ReplaceWithSecretsManager!"

  storage_encrypted   = true
  deletion_protection = true

  backup_retention_period = 7
  # ✗ VIOLATION — preferred_backup_window is missing (random AWS-chosen time)

  skip_final_snapshot = true

  tags = {
    Environment = "production"
    Owner       = "orders-team@company.com"
    Application = "orders-service"
    CostCenter  = "CC-1002"
  }
}
