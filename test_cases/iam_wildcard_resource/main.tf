# test_cases/iam_wildcard_resource/main.tf
# Expected: FAIL — iam_least_privilege policy
# IAM inline policy grants full s3:* on resource "*" — violates least-privilege.

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "app-service-role" {
  name = "app-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}

resource "aws_iam_role_policy" "app-service-policy" {
  name = "app-service-policy"
  role = aws_iam_role.app-service-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*" # ✗ overly broad action
        Resource = "*"    # ✗ VIOLATION — wildcard resource, iam_least_privilege policy
      }
    ]
  })
}
