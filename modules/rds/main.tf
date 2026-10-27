# ==============================================================================
# MODULE: RDS (Relational Database Service)
# PURPOSE: Create a MySQL primary instance + 2 read replicas.
#          Password is supplied from module.secrets_manager — never plain text.
#
# APPLY ORDER  : secrets_manager → networking → security → rds
# DESTROY ORDER: cloudwatch → rds → secrets_manager
#                (alarms reference rds_instance_id; rds refs the secret)
#
# CONCEPTS: count, lifecycle, depends_on, sensitive variable
# ==============================================================================

# ------------------------------------------------------------------------------
# DB SUBNET GROUP
# RDS requires subnets in at least 2 AZs for Multi-AZ and read replica placement.
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.environment}-db-subnet-group"
  subnet_ids  = var.private_subnet_ids
  description = "DB subnet group for ${var.environment}"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-db-subnet-group"
  })
}

# ------------------------------------------------------------------------------
# DB PARAMETER GROUP
# Customise MySQL settings without modifying the engine directly.
# ------------------------------------------------------------------------------
resource "aws_db_parameter_group" "main" {
  name        = "${var.environment}-mysql-params"
  family      = "mysql8.0"
  description = "MySQL 8 parameters for ${var.environment}"

  # Example: enable slow query log for performance debugging
  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"   # log queries taking > 2 seconds
  }

  # CONCEPT: lifecycle — changing a parameter group requires a new one
  lifecycle {
    create_before_destroy = true
  }

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# PRIMARY RDS INSTANCE
# This is the read-write master. Replicas below will replicate from it.
# ------------------------------------------------------------------------------
resource "aws_db_instance" "primary" {
  identifier = "${var.environment}-mysql-primary"

  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_storage_gb
  storage_type         = "gp3"
  storage_encrypted    = true   # encrypt the database at rest

  db_name  = var.db_name
  username = var.db_username
  # Password comes from module.secrets_manager — never stored in tfvars or state plain text.
  # var.db_password is marked sensitive=true and sourced from the secrets_manager module output.
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name

  # Backups: keep 7 days of automated snapshots
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"   # UTC — low traffic window
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Multi-AZ creates a standby replica in another AZ for high availability
  multi_az = var.multi_az_enabled

  # Enable deletion protection in production to prevent accidental drops
  deletion_protection = var.deletion_protection

  # CONCEPT: lifecycle — snapshot on destroy so you don't lose data
  lifecycle {
    prevent_destroy       = false          # set true in prod
    ignore_changes        = [password]     # don't detect Secrets Manager rotations
  }

  # CONCEPT: depends_on — wait for the Secrets Manager secret version to exist
  # before creating RDS. Without this, RDS could start before the password is written.
  depends_on = [var.secret_version_dependency]

  # Don't make the DB publicly accessible — it lives in private subnets
  publicly_accessible = false

  # Automatically upgrade minor versions (e.g. 8.0.32 → 8.0.33)
  auto_minor_version_upgrade = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-mysql-primary"
    Role = "primary"
  })
}

# ------------------------------------------------------------------------------
# READ REPLICAS — 2 cross-region replicas
# CONCEPT: count — create N replicas from one resource block
#
# Each replica uses a different provider alias (region) defined in the
# calling environment's providers.tf. This demonstrates cross-region replication.
#
# NOTE: Cross-region replicas require the source DB ARN (not ID).
#       The provider for each replica must be passed in.
# ------------------------------------------------------------------------------

# Replica 1 — same region as primary (availability read scaling)
resource "aws_db_instance" "replica" {
  # CONCEPT: count — create var.replica_count replicas
  count = var.replica_count

  identifier = "${var.environment}-mysql-replica-${count.index}"

  # Point to the primary instance as the replication source
  replicate_source_db = aws_db_instance.primary.identifier

  instance_class = var.replica_instance_class
  storage_type   = "gp3"

  # Read replicas inherit the engine, storage, and network from the source
  # Do NOT specify db_name, username, password, or subnet_group for replicas

  vpc_security_group_ids = [var.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name

  # Replicas should not have automated backups (reduces cost and latency)
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  auto_minor_version_upgrade = true
  publicly_accessible        = false

  # CONCEPT: depends_on — replica needs the primary to exist and be available
  depends_on = [aws_db_instance.primary]

  # CONCEPT: lifecycle — ignore changes the primary pushes to replicas
  lifecycle {
    ignore_changes = [
      replicate_source_db,  # AWS manages replication config after creation
    ]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-mysql-replica-${count.index}"
    Role = "read-replica"
  })
}
