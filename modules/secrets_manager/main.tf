# ==============================================================================
# MODULE: Secrets Manager
# PURPOSE: Securely store the RDS master password in AWS Secrets Manager.
#          The RDS module reads the password from here instead of receiving it
#          as a plain-text Terraform variable.
#
# APPLY ORDER  : Secrets Manager → RDS (RDS reads the secret at creation time)
# DESTROY ORDER: RDS must be destroyed BEFORE Secrets Manager
#                (active DB connections reference the secret)
#
# CONCEPTS: resource, data source, lifecycle, sensitive output, random_password
# ==============================================================================

# ------------------------------------------------------------------------------
# RANDOM PASSWORD GENERATOR
# Terraform generates a cryptographically secure random password.
# We never have to type or store a password anywhere in code.
# ------------------------------------------------------------------------------
resource "random_password" "rds" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"   # exclude chars that break MySQL CLI

  # CONCEPT: lifecycle keep_alive — the password is regenerated ONLY if you
  # explicitly taint this resource. Normal applies never rotate it.
  lifecycle {
    ignore_changes = [length, special, override_special]
  }
}

# ------------------------------------------------------------------------------
# SECRETS MANAGER SECRET (the container / metadata)
# This just defines the secret name and settings.
# The actual value is stored in aws_secretsmanager_secret_version below.
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "rds_password" {
  name        = "${var.environment}/rds/master-password"
  description = "RDS master password for ${var.environment} MySQL instance"

  # How long AWS retains a deleted secret before permanent removal.
  # Set to 0 for immediate deletion (useful in dev/test).
  # In prod, set to 30 days so you can recover an accidentally deleted secret.
  recovery_window_in_days = var.recovery_window_days

  # CONCEPT: lifecycle — if you change the secret name, create the new one first
  # so there's no gap where the secret doesn't exist.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-rds-master-password"
    Service = "rds"
  })
}

# ------------------------------------------------------------------------------
# SECRET VERSION (the actual password value stored in the secret)
# Stored as a JSON string so you can add more fields later (e.g. username, host).
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id

  # Store as JSON — makes it easy to read individual fields in application code
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.rds.result
    engine   = "mysql"
    port     = 3306
  })

  # CONCEPT: lifecycle — do not rotate the secret automatically on every plan/apply.
  # Once set, only explicit resource taint will change the password.
  lifecycle {
    ignore_changes = [secret_string]
  }

  depends_on = [aws_secretsmanager_secret.rds_password]
}

# ------------------------------------------------------------------------------
# IAM POLICY: Allow EC2 and EKS nodes to READ this specific secret
# Least-privilege: only GetSecretValue on THIS secret, nothing else.
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "read_rds_secret" {
  statement {
    sid    = "AllowReadRDSSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.rds_password.arn]
  }
}

resource "aws_iam_policy" "read_rds_secret" {
  name        = "${var.environment}-read-rds-secret-policy"
  description = "Allow reading the RDS master password secret"
  policy      = data.aws_iam_policy_document.read_rds_secret.json

  tags = var.common_tags
}
