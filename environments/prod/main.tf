# ==============================================================================
# ENVIRONMENT: prod — Module Orchestration
#
# APPLY ORDER:
#   1. storage → 2. sns → 3. secrets_manager → 4. networking → 5. security
#   → 6. iam → 7. compute → 8. eks → 9. rds → 10. cloudwatch
#
# DESTROY ORDER (reverse, enforced by depends_on):
#   cloudwatch → rds → eks → compute → iam → security → networking
#   → secrets_manager → sns → storage
# ==============================================================================

module "storage" {
  source = "../../modules/storage"

  environment        = var.environment
  bucket_name_prefix = var.bucket_name_prefix
  versioning_enabled = true
  common_tags        = local.common_tags
}

module "sns" {
  source = "../../modules/sns"

  environment           = var.environment
  alert_email_addresses = var.alert_email_addresses
  common_tags           = local.common_tags
}

module "secrets_manager" {
  source = "../../modules/secrets_manager"

  environment          = var.environment
  db_username          = var.db_username
  recovery_window_days = 30   # prod: 30-day recovery window for safety
  common_tags          = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  common_tags          = local.common_tags
}

module "security" {
  source = "../../modules/security"

  environment = var.environment
  vpc_id      = module.networking.vpc_id
  common_tags = local.common_tags

  depends_on = [module.networking]
}

module "iam" {
  source = "../../modules/iam"

  environment             = var.environment
  s3_bucket_arn           = module.storage.bucket_arn
  secrets_read_policy_arn = module.secrets_manager.read_policy_arn
  common_tags             = local.common_tags

  depends_on = [module.storage, module.secrets_manager]
}

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
  public_access_enabled     = false   # prod: no public API endpoint
  common_tags               = local.common_tags

  depends_on = [module.networking, module.security, module.iam]
}

module "rds" {
  source = "../../modules/rds"

  environment               = var.environment
  private_subnet_ids        = module.networking.private_subnet_ids
  rds_security_group_id     = module.security.rds_security_group_id
  db_instance_class         = var.db_instance_class
  db_username               = var.db_username
  db_password               = module.secrets_manager.rds_password
  secret_version_dependency = module.secrets_manager
  multi_az_enabled          = true    # prod: standby in second AZ
  deletion_protection       = true    # prod: block accidental destroy
  replica_count             = var.replica_count
  common_tags               = local.common_tags

  depends_on = [module.networking, module.security, module.secrets_manager]
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  environment      = var.environment
  aws_region       = var.aws_region
  ec2_instance_id  = module.compute.instance_ids[0]
  eks_cluster_name = module.eks.cluster_name
  nat_gateway_id   = module.networking.nat_gateway_id
  rds_instance_id  = module.rds.primary_instance_id
  alarm_sns_arn    = module.sns.topic_arn
  common_tags      = local.common_tags

  depends_on = [module.sns, module.compute, module.eks, module.rds]
}
