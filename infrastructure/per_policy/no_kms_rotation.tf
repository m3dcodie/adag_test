# per_policy/no_kms_rotation.tf
# Expected: 1 violation — kms_key_rotation
resource "aws_kms_key" "prod-api-kms-primary" {
  description             = "KMS key for production"
  deletion_window_in_days = 30
  enable_key_rotation     = false # ✗ VIOLATION

  tags = {
    Environment = "production"
    Owner       = "security-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}
