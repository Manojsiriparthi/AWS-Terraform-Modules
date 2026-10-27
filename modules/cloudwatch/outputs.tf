# ==============================================================================
# MODULE: CloudWatch — Outputs
# ==============================================================================

output "ec2_dashboard_name" {
  description = "Name of the EC2 CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.ec2.dashboard_name
}

output "eks_dashboard_name" {
  description = "Name of the EKS CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.eks.dashboard_name
}

output "networking_dashboard_name" {
  description = "Name of the Networking CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.networking.dashboard_name
}

output "alarm_arns" {
  description = "Map of alarm name → ARN for all created alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.alarms : k => v.arn }
}
