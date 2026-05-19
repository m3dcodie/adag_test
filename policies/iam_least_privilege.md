# IAM Least Privilege Policy

## Policy ID

`iam_least_privilege`

## Severity

**HIGH**

## Description

All IAM policies and inline role policies MUST follow the principle of least privilege. Wildcard resources (`"*"`) MUST NOT be used in `Allow` statements unless the action inherently requires it (e.g., `iam:ListAccountAliases`). Overly broad actions (e.g., `s3:*`, `ec2:*`, `*`) combined with wildcard resources are strictly forbidden.

## Scope

This policy applies to the following AWS resources:

- `aws_iam_policy` (Standalone IAM managed policies)
- `aws_iam_role_policy` (Inline policies attached to IAM roles)
- `aws_iam_user_policy` (Inline policies attached to IAM users)
- `aws_iam_group_policy` (Inline policies attached to IAM groups)

## Requirements

1. **No wildcard resource with broad actions:** `Allow` statements MUST NOT combine a wildcard `Action` (e.g., `s3:*`, `*`) with `Resource: "*"`.
2. **Scoped resources:** Wherever possible, resource ARNs must be scoped to specific resources (e.g., `arn:aws:s3:::my-bucket/*`).
3. **Action granularity:** Prefer specific actions (e.g., `s3:GetObject`, `s3:PutObject`) over service-wide wildcards.
4. **Exception:** Actions that are inherently global (e.g., `iam:ListAccountAliases`, `sts:GetCallerIdentity`) may use `Resource: "*"` but MUST NOT be combined with broad action wildcards.

## Rationale

Least-privilege IAM is critical for:

1. **Blast radius reduction:** Compromised credentials with wildcard access can affect every resource in the account.
2. **Compliance:** Required by CIS AWS Foundations Benchmark, NIST 800-53, PCI-DSS, and SOC 2.
3. **Audit clarity:** Scoped policies make it obvious what a role can and cannot do.
4. **Privilege escalation prevention:** Wildcards like `iam:*` on `*` can allow attackers to escalate privileges.

## Examples

### ✅ Compliant — Scoped S3 access

```hcl
resource "aws_iam_role_policy" "app-s3-read" {
  name = "app-s3-read"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]   # ✓ specific actions
        Resource = [
          "arn:aws:s3:::my-app-bucket",                # ✓ specific resource
          "arn:aws:s3:::my-app-bucket/*"
        ]
      }
    ]
  })
}
```

### ✅ Compliant — Global action exception

```hcl
resource "aws_iam_role_policy" "read-account-info" {
  name = "read-account-info"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:ListAccountAliases"  # ✓ inherently global, no scoping possible
        Resource = "*"
      }
    ]
  })
}
```

### ❌ Non-Compliant — Wildcard action + wildcard resource

```hcl
resource "aws_iam_role_policy" "overprivileged" {
  name = "overprivileged"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*"   # ✗ overly broad service wildcard
        Resource = "*"      # ✗ wildcard resource — VIOLATION
      }
    ]
  })
}
```

### ❌ Non-Compliant — Full admin

```hcl
resource "aws_iam_role_policy" "admin" {
  policy = jsonencode({
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"   # ✗ full admin action
        Resource = "*"  # ✗ wildcard resource — VIOLATION
      }
    ]
  })
}
```

## Remediation

1. Replace `Resource: "*"` with the specific ARN(s) of the resources being accessed.
2. Replace wildcard actions (e.g., `s3:*`) with a minimal list of required actions.
3. Use IAM Access Analyzer to generate least-privilege policies based on actual usage.
