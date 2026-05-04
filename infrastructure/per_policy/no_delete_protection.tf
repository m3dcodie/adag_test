# per_policy/no_delete_protection.tf
# Expected: 1 violation — delete_protection
resource "aws_db_instance" "prod-api-db-primary" {
  identifier        = "prod-api-db-primary"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = false # ✗ VIOLATION

  backup_retention_period = 14
  backup_window           = "03:00-04:00"
  multi_az                = true
  publicly_accessible     = false
  skip_final_snapshot     = true

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}
