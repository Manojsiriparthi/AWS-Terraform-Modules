locals {
  common_tags = {
    Environment = var.environment
    Project     = "terraform-learning"
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}
