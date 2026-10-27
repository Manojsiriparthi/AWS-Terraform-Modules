# ==============================================================================
# MODULE: EKS — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster (e.g. '1.29')"
  type        = string
  default     = "1.29"
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS cluster control plane"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for the EKS worker nodes"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where the nodes will run"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security group ID for the EKS control plane"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_disk_size" {
  description = "Disk size for each worker node in GB"
  type        = number
  default     = 20
}

variable "node_desired_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "public_access_enabled" {
  description = "Allow public endpoint access to the EKS API server"
  type        = bool
  default     = true   # Set false in production for extra security
}

# CONCEPT: complex map variable for add-ons
variable "eks_addons" {
  description = "Map of EKS add-ons to install. Key = addon name, value = config object."
  type = map(object({
    version = string
  }))
  default = {
    "coredns" = {
      version = "v1.11.1-eksbuild.4"
    }
    "kube-proxy" = {
      version = "v1.29.0-eksbuild.1"
    }
    "vpc-cni" = {
      version = "v1.16.0-eksbuild.1"
    }
    "aws-ebs-csi-driver" = {
      version = "v1.26.0-eksbuild.1"
    }
  }
}

# Dependency handles — used in depends_on to handle implicit dependencies
variable "cluster_role_policy_dependency" {
  description = "Pass the IAM role policy attachments here to enforce ordering"
  type        = any
  default     = null
}

variable "node_role_policy_dependency" {
  description = "Pass the node IAM role policy attachments here to enforce ordering"
  type        = any
  default     = null
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
