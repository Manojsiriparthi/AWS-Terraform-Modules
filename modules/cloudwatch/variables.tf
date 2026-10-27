# ==============================================================================
# MODULE: CloudWatch — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in dashboard JSON)"
  type        = string
  default     = "us-east-1"
}

variable "ec2_instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name for Container Insights metrics"
  type        = string
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID for networking alarms"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier for DB alarms"
  type        = string
  default     = "placeholder-rds-id"   # override in env tfvars
}

variable "alarm_sns_arn" {
  description = <<-EOT
    SNS topic ARN for alarm notifications.
    Always sourced from module.sns.topic_arn — do not set manually.
    Pass an empty string "" only to intentionally disable notifications (not recommended).
  EOT
  type    = string
  default = ""
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
