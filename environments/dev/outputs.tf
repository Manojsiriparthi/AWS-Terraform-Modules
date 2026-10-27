# ==============================================================================
# ENVIRONMENT: dev — Outputs
# ==============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "ec2_public_ips" {
  description = "Public IPs of EC2 instances"
  value       = module.compute.public_ips
}

output "ec2_instance_ids" {
  description = "EC2 instance IDs"
  value       = module.compute.instance_ids
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "rds_primary_endpoint" {
  description = "RDS primary connection endpoint"
  value       = module.rds.primary_endpoint
}

output "rds_replica_endpoints" {
  description = "RDS read replica endpoints"
  value       = module.rds.replica_endpoints
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = module.storage.bucket_id
}

# ---- SNS ----
output "sns_topic_arn" {
  description = "SNS topic ARN used by CloudWatch alarms"
  value       = module.sns.topic_arn
}

output "sns_topic_name" {
  description = "SNS topic name"
  value       = module.sns.topic_name
}

# ---- Secrets Manager ----
output "rds_secret_name" {
  description = "Secrets Manager secret name containing the RDS password"
  value       = module.secrets_manager.secret_name
}

output "rds_secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = module.secrets_manager.secret_arn
}

# ---- CloudWatch ----
output "cloudwatch_dashboards" {
  description = "Names of created CloudWatch dashboards"
  value = {
    ec2        = module.cloudwatch.ec2_dashboard_name
    eks        = module.cloudwatch.eks_dashboard_name
    networking = module.cloudwatch.networking_dashboard_name
  }
}

output "cloudwatch_alarm_arns" {
  description = "Map of alarm key → ARN for all 10 CloudWatch alarms"
  value       = module.cloudwatch.alarm_arns
}
