# test_cases/sg_ssh_open_world/main.tf
# Expected: FAIL — public_access_block policy (security group ingress on port 22 from 0.0.0.0/0)
# The public_access_block policy explicitly covers security groups with unrestricted ingress on sensitive ports.

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "app-server-sg" {
  name        = "app-server-sg"
  description = "Security group for application servers"
  vpc_id      = "vpc-00000000000000001"

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # ✗ VIOLATION — unrestricted SSH, public_access_block policy
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # acceptable for a public-facing HTTPS endpoint
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "production"
    Owner       = "infra-team@company.com"
    Application = "core-api"
    CostCenter  = "CC-1001"
  }
}
