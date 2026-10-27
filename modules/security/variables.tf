# ==============================================================================
# MODULE: Security — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups are created"
  type        = string
}

# CONCEPT: complex type — list of objects
# Each object represents one ingress rule, making it easy to add/remove ports.
variable "ec2_ingress_rules" {
  description = "List of ingress rules for the EC2 security group"
  type = list(object({
    port        = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      port        = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]   # Restrict this to your IP in production!
      description = "SSH access"
    },
    {
      port        = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS"
    },
    {
      port        = 8080
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Jenkins web UI"
    }
  ]
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
