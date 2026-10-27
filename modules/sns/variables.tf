# ==============================================================================
# MODULE: SNS — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name (dev / test / prod)"
  type        = string
}

variable "alert_email_addresses" {
  description = <<-EOT
    List of email addresses to subscribe to the alerts topic.
    Each address receives a confirmation email from AWS — they must click the link.
    Example: ["ops@example.com", "devteam@example.com"]
  EOT
  type    = list(string)
  default = []
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
