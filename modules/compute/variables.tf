# ==============================================================================
# MODULE: Compute — Variables
# Define all inputs this module accepts. Callers (environments) supply values.
# ==============================================================================

variable "environment" {
  description = "Deployment environment name (dev / test / prod)"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair to create in AWS"
  type        = string
  default     = "devops"
}

variable "public_key_path" {
  description = "Local path to your PUBLIC SSH key (e.g. ~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "instance_type" {
  description = "EC2 instance size (e.g. t3.medium)"
  type        = string
  default     = "t3.medium"
}

variable "instance_count" {
  description = "Number of EC2 instances to create — demonstrates the count concept"
  type        = number
  default     = 1
}

variable "public_subnet_id" {
  description = "Subnet ID where the instance will be launched"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to the instance"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name for SSM Session Manager access"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 30
}

variable "internet_gateway_id" {
  description = "Internet Gateway ID — used in depends_on for EIP"
  type        = string
}

variable "common_tags" {
  description = "Map of tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
