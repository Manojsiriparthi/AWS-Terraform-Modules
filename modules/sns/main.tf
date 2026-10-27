# ==============================================================================
# MODULE: SNS (Simple Notification Service)
# PURPOSE: Create an SNS topic that CloudWatch alarms publish to,
#          and subscribe one or more email addresses to receive alerts.
#
# APPLY ORDER  : SNS must exist BEFORE CloudWatch (alarms need the topic ARN)
# DESTROY ORDER: CloudWatch alarms must be destroyed BEFORE SNS topic
#                (alarms hold a reference to the topic ARN)
#
# CONCEPTS: resource, for_each on subscriptions, lifecycle, output
# ==============================================================================

# ------------------------------------------------------------------------------
# SNS TOPIC
# The "mailbox" that receives alarm notifications.
# CloudWatch publishes a message here; subscribers (email, Lambda, etc.) receive it.
# ------------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name         = "${var.environment}-alerts"
  display_name = "${var.environment} Infrastructure Alerts"

  # CONCEPT: lifecycle — keep the topic alive even if someone tries a partial destroy.
  # CloudWatch alarms reference this ARN; destroying the topic first would break them.
  lifecycle {
    # Prevent destroy is intentionally false so `terraform destroy` still works.
    # The environment main.tf enforces ordering via depends_on on the cloudwatch module.
    prevent_destroy = false
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-alerts-topic"
  })
}

# ------------------------------------------------------------------------------
# SNS TOPIC POLICY
# Allow CloudWatch (and optionally other AWS services) to publish to this topic.
# Without this policy CloudWatch cannot send alarm notifications.
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow CloudWatch to publish alarm state changes
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        # Allow the owning account to manage subscriptions, publish manually, etc.
        Sid    = "AllowOwnerAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "SNS:*"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# EMAIL SUBSCRIPTIONS
# CONCEPT: for_each — subscribe every email in the list with one resource block.
# AWS sends a confirmation email; the subscriber must click "Confirm subscription".
# ------------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "email" {
  # for_each on a set of strings — each.key == each.value == email address
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value   # the email address

  # CONCEPT: depends_on — subscription must be created after the topic policy
  # so the topic is fully configured before subscriptions are attached.
  depends_on = [aws_sns_topic_policy.alerts]
}
