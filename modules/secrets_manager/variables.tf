# ==============================================================================
# MODULE: Secrets Manager — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name (dev / test / prod)"
  type        = string
}

variable "db_username" {
  description = "RDS master username stored alongside the password in the secret"
  type        = string
  default     = "admin"
}

variable "recovery_window_days" {
  description = <<-EOT
    Days AWS retains a deleted secret before permanent removal.
    Set 0 for immediate deletion (dev/test). Set 30 for prod recovery safety.
  EOT
  type    = number
  default = 0   # immediate for dev — override to 30 in prod tfvars
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
