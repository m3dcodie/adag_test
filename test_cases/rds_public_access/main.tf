# test_cases/rds_public_access/main.tf
# Expected: FAIL — public_access_block policy
# All other policies satisfied; only publicly_accessible = true triggers a violation.

provider "aws" {
  region = "us-east-1"
}

resource "aws_db_instance" "prod-api-db-primary" {
  identifier        = "prod-api-db-primary"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.r5.large"
  allocated_storage = 100

  storage_encrypted   = true
  deletion_protection = true

  backup_retention_period = 14
  backup_window           = "03:00-04:00"

  multi_az            = true
  publicly_accessible = true # ✗ VIOLATION — public_access_block policy
  skip_final_snapshot = true

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}
