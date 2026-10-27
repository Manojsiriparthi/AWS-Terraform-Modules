output "vpc_id"               { value = module.networking.vpc_id }
output "ec2_public_ips"       { value = module.compute.public_ips }
output "ec2_instance_ids"     { value = module.compute.instance_ids }
output "eks_cluster_name"     { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "rds_primary_endpoint" { value = module.rds.primary_endpoint }
output "rds_replica_endpoints"{ value = module.rds.replica_endpoints }
output "s3_bucket_name"       { value = module.storage.bucket_id }
output "sns_topic_arn"        { value = module.sns.topic_arn }
output "rds_secret_name"      { value = module.secrets_manager.secret_name }
output "rds_secret_arn"       { value = module.secrets_manager.secret_arn }
output "cloudwatch_dashboards" {
  value = {
    ec2        = module.cloudwatch.ec2_dashboard_name
    eks        = module.cloudwatch.eks_dashboard_name
    networking = module.cloudwatch.networking_dashboard_name
  }
}
output "cloudwatch_alarm_arns" { value = module.cloudwatch.alarm_arns }
