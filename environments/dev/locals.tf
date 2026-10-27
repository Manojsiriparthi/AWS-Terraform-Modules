# ==============================================================================
# ENVIRONMENT: dev — Local Values
# CONCEPT: locals — computed values shared across the environment
# ==============================================================================

locals {
  # Common tags applied to EVERY resource in this environment.
  # This ensures you can filter all dev resources in the AWS console.
  common_tags = {
    Environment = var.environment
    Project     = "terraform-learning"
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}
