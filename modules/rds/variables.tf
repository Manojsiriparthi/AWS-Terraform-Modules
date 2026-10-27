# ==============================================================================
# MODULE: RDS — Variables
# ==============================================================================

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group (need 2+ AZs)"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID to attach to RDS instances"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class for the primary (e.g. db.t3.micro)"
  type        = string
  default     = "db.t3.micro"
}

variable "replica_instance_class" {
  description = "RDS instance class for read replicas"
  type        = string
  default     = "db.t3.micro"
}

variable "db_storage_gb" {
  description = "Allocated storage for primary instance in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = <<-EOT
    RDS master password. In this repo this is always sourced from
    module.secrets_manager.rds_password — never set manually in tfvars.
    Marked sensitive so Terraform never prints it in plan/apply output.
  EOT
  type      = string
  sensitive = true
}

# CONCEPT: dependency handle variable
# Terraform can't always infer depends_on across module boundaries.
# Passing the secret version resource as "any" type lets the RDS module
# explicitly wait for the secret to be fully written before the DB is created.
variable "secret_version_dependency" {
  description = "Pass aws_secretsmanager_secret_version resource here to enforce ordering"
  type        = any
  default     = null
}

variable "backup_retention_days" {
  description = "Number of days to keep automated backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ for high availability (recommended for prod)"
  type        = bool
  default     = false   # set true in prod
}

variable "deletion_protection" {
  description = "Prevent the DB from being deleted via Terraform"
  type        = bool
  default     = false   # set true in prod
}

# CONCEPT: count variable — controls number of read replicas
variable "replica_count" {
  description = "Number of read replicas to create (demonstrates count)"
  type        = number
  default     = 2
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
