# ==============================================================================
# MODULE: SNS — Outputs
# The topic ARN is the key output — passed into the CloudWatch module so alarms
# know where to publish notifications.
# ==============================================================================

output "topic_arn" {
  description = "ARN of the SNS alerts topic — pass this to module.cloudwatch"
  value       = aws_sns_topic.alerts.arn
}

output "topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.alerts.name
}

output "subscription_arns" {
  description = "Map of email → subscription ARN for all email subscriptions"
  value       = { for k, v in aws_sns_topic_subscription.email : k => v.arn }
}
