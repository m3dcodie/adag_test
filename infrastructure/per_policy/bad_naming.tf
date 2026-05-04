# per_policy/bad_naming.tf
# Expected: 1 violation — naming_conventions
# identifier uses underscores and uppercase — should be kebab-case lowercase
resource "aws_db_instance" "ProdDB_Instance_01" {
  identifier        = "ProdDB_Instance_01" # ✗ VIOLATION — must be prod-db-instance-01
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = true

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
