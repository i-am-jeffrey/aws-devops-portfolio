resource "aws_kms_key" "ecr" {
  description             = "${var.project_name} ECR repository encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Fixes CKV2_AWS_64 -- without an explicit policy, AWS silently applies
  # this exact same default (full access for the account root) anyway.
  # This just makes that default visible to Checkov instead of implicit.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMAccountRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.project_name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # allows `terraform destroy` to remove this repo even with images inside --
                               # fine for an iterative learning project; a real prod repo would likely
                               # leave this false to prevent accidental image loss

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}
