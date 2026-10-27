# ==============================================================================
# MODULE: IAM — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket EC2 should have access to"
  type        = string
}

variable "secrets_read_policy_arn" {
  description = <<-EOT
    IAM policy ARN (from module.secrets_manager.read_policy_arn) that grants
    EC2 GetSecretValue on the RDS password secret.
    Leave empty string "" to skip attachment (not recommended).
  EOT
  type    = string
  default = ""
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
