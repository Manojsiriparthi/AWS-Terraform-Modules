# ==============================================================================
# MODULE: Storage — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (a random suffix is appended)"
  type        = string
  default     = "my-terraform-bucket"
}

variable "versioning_enabled" {
  description = "Enable S3 versioning (recommended for prod)"
  type        = bool
  default     = true
}

# CONCEPT: complex variable type — list of objects
variable "lifecycle_rules" {
  description = "List of lifecycle rules for the S3 bucket"
  type = list(object({
    id              = string
    enabled         = bool
    prefix          = string   # apply to objects with this key prefix
    transition_days = number   # days before moving to STANDARD_IA (0 = no transition)
    expiration_days = number   # days before deleting (0 = no expiration)
  }))
  default = [
    {
      id              = "logs-lifecycle"
      enabled         = true
      prefix          = "logs/"
      transition_days = 30    # move logs to cheaper storage after 30 days
      expiration_days = 365   # delete logs after 1 year
    },
    {
      id              = "tmp-cleanup"
      enabled         = true
      prefix          = "tmp/"
      transition_days = 0
      expiration_days = 7     # delete temp files after 7 days
    }
  ]
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
