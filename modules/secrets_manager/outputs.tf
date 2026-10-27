# ==============================================================================
# MODULE: Secrets Manager — Outputs
# ==============================================================================

# The plain-text password — marked sensitive so Terraform never prints it.
# Passed directly into the RDS module as db_password.
output "rds_password" {
  description = "Generated RDS master password (sensitive — never printed in logs)"
  value       = random_password.rds.result
  sensitive   = true   # CONCEPT: sensitive output — Terraform redacts this in plans
}

# The secret ARN — used in IAM policies to grant access to this specific secret.
output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.rds_password.arn
}

# The secret name — useful for app code that retrieves the secret by name.
output "secret_name" {
  description = "Name/path of the secret (e.g. dev/rds/master-password)"
  value       = aws_secretsmanager_secret.rds_password.name
}

# The IAM policy ARN — attach this to any role that needs to read the password.
output "read_policy_arn" {
  description = "IAM policy ARN that grants GetSecretValue on this secret"
  value       = aws_iam_policy.read_rds_secret.arn
}
