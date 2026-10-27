# ==============================================================================
# ENVIRONMENT: dev — Module Orchestration
#
# APPLY ORDER (each module depends_on the ones above it):
#   1. storage          — S3 bucket (IAM needs its ARN)
#   2. sns              — Alert topic (CloudWatch needs its ARN; must exist BEFORE CW)
#   3. secrets_manager  — RDS password (RDS reads it on creation)
#   4. networking       — VPC / subnets / IGW / NAT (everything else needs the VPC)
#   5. security         — Security groups (need the VPC ID from networking)
#   6. iam              — Roles & policies (needs S3 ARN + secrets policy ARN)
#   7. compute          — EC2 instances (needs subnet, SG, IAM profile)
#   8. eks              — Cluster + nodes (needs subnets, SG, IAM roles)
#   9. rds              — MySQL + replicas (needs subnets, SG, password from secrets)
#  10. cloudwatch       — Dashboards + alarms (needs IDs from all above + SNS ARN)
#
# DESTROY ORDER is the exact reverse — Terraform handles this automatically
# because of the depends_on chain. CloudWatch is destroyed first (it refs SNS),
# then RDS (refs secrets), then EKS/compute, then networking, then SNS/secrets.
# ==============================================================================

# ==============================================================================
# STEP 1 — STORAGE
# No dependencies. Must be first so IAM can reference the bucket ARN.
# ==============================================================================
module "storage" {
  source = "../../modules/storage"

  environment        = var.environment
  bucket_name_prefix = var.bucket_name_prefix
  versioning_enabled = true
  common_tags        = local.common_tags
}

# ==============================================================================
# STEP 2 — SNS
# No dependencies on other infra. Created early so CloudWatch can reference it.
# DESTROY: Terraform destroys CloudWatch FIRST (depends on SNS), then SNS.
# ==============================================================================
module "sns" {
  source = "../../modules/sns"

  environment           = var.environment
  alert_email_addresses = var.alert_email_addresses
  common_tags           = local.common_tags
}

# ==============================================================================
# STEP 3 — SECRETS MANAGER
# Generates and stores the RDS password before the database is created.
# DESTROY: RDS is destroyed before secrets_manager because rds depends_on it.
# ==============================================================================
module "secrets_manager" {
  source = "../../modules/secrets_manager"

  environment          = var.environment
  db_username          = var.db_username
  recovery_window_days = 0   # immediate deletion for dev (set 30 for prod)
  common_tags          = local.common_tags
}

# ==============================================================================
# STEP 4 — NETWORKING
# VPC, subnets, IGW, NAT GW, route tables.
# Everything else depends on this — it must be created before SGs and EC2.
# ==============================================================================
module "networking" {
  source = "../../modules/networking"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  common_tags          = local.common_tags
}

# ==============================================================================
# STEP 5 — SECURITY GROUPS
# Needs the VPC ID from networking.
# All compute resources (EC2, RDS, EKS) depend on their respective SGs.
# ==============================================================================
module "security" {
  source = "../../modules/security"

  environment = var.environment
  vpc_id      = module.networking.vpc_id
  common_tags = local.common_tags

  depends_on = [module.networking]
}

# ==============================================================================
# STEP 6 — IAM
# Needs: S3 bucket ARN (from storage) + Secrets Manager read policy ARN.
# EC2 and EKS depend on these roles — they must exist first.
# ==============================================================================
module "iam" {
  source = "../../modules/iam"

  environment             = var.environment
  s3_bucket_arn           = module.storage.bucket_arn
  # Attach the Secrets Manager read policy to EC2 so instances can fetch the DB password
  secrets_read_policy_arn = module.secrets_manager.read_policy_arn
  common_tags             = local.common_tags

  # CONCEPT: depends_on — IAM policy attachments need both the role (created here)
  # and the external policy (from secrets_manager) to exist first.
  depends_on = [module.storage, module.secrets_manager]
}

# ==============================================================================
# STEP 7 — COMPUTE (EC2)
# Needs: subnet (networking), SG (security), IAM profile (iam), IGW (networking).
# ==============================================================================
module "compute" {
  source = "../../modules/compute"

  environment          = var.environment
  key_name             = var.key_name
  public_key_path      = var.public_key_path
  instance_type        = var.instance_type
  instance_count       = var.instance_count
  public_subnet_id     = module.networking.public_subnet_ids[0]
  security_group_id    = module.security.ec2_security_group_id
  iam_instance_profile = module.iam.ec2_instance_profile_name
  internet_gateway_id  = module.networking.internet_gateway_id
  common_tags          = local.common_tags

  depends_on = [module.networking, module.security, module.iam]
}

# ==============================================================================
# STEP 8 — EKS
# Needs: private subnets (networking), cluster SG (security), IAM roles (iam).
# ==============================================================================
module "eks" {
  source = "../../modules/eks"

  environment               = var.environment
  kubernetes_version        = var.kubernetes_version
  cluster_role_arn          = module.iam.eks_cluster_role_arn
  node_role_arn             = module.iam.eks_nodes_role_arn
  private_subnet_ids        = module.networking.private_subnet_ids
  cluster_security_group_id = module.security.eks_cluster_security_group_id
  node_instance_type        = var.node_instance_type
  node_desired_count        = var.node_desired_count
  node_min_count            = var.node_min_count
  node_max_count            = var.node_max_count
  common_tags               = local.common_tags

  depends_on = [module.networking, module.security, module.iam]
}

# ==============================================================================
# STEP 9 — RDS
# Needs: private subnets (networking), SG (security), password (secrets_manager).
# DESTROY: cloudwatch → rds → secrets_manager (enforced by depends_on chain)
# ==============================================================================
module "rds" {
  source = "../../modules/rds"

  environment           = var.environment
  private_subnet_ids    = module.networking.private_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id
  db_instance_class     = var.db_instance_class
  db_username           = var.db_username

  # Password comes entirely from Secrets Manager — no plain-text password in tfvars
  db_password = module.secrets_manager.rds_password

  # Pass the secret version resource as a dependency handle so RDS waits for
  # the secret to be fully written before the DB instance is created.
  secret_version_dependency = module.secrets_manager

  multi_az_enabled    = false   # single-AZ is fine for dev
  deletion_protection = false
  replica_count       = var.replica_count
  common_tags         = local.common_tags

  depends_on = [
    module.networking,
    module.security,
    module.secrets_manager,   # password must be in Secrets Manager before DB is created
  ]
}

# ==============================================================================
# STEP 10 — CLOUDWATCH
# Needs: EC2 ID (compute), EKS name (eks), NAT ID (networking),
#        RDS ID (rds), SNS ARN (sns).
# DESTROY: cloudwatch is destroyed FIRST because it holds references to SNS + RDS.
# ==============================================================================
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment      = var.environment
  aws_region       = var.aws_region
  ec2_instance_id  = module.compute.instance_ids[0]
  eks_cluster_name = module.eks.cluster_name
  nat_gateway_id   = module.networking.nat_gateway_id
  rds_instance_id  = module.rds.primary_instance_id

  # SNS ARN comes from the sns module — no manual ARN in tfvars
  alarm_sns_arn = module.sns.topic_arn

  common_tags = local.common_tags

  # CloudWatch alarms reference SNS topic + RDS + EKS + EC2.
  # All must exist before CW is created, and CW must be destroyed first.
  depends_on = [
    module.sns,
    module.compute,
    module.eks,
    module.rds,
  ]
}
