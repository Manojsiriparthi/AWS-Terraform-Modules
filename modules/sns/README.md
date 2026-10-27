# 📣 Module: SNS (Simple Notification Service)

> **Spoon-feeding guide — every single line explained.**

---

## 📦 What Does This Module Create?

| Resource | What it is |
|----------|-----------|
| `aws_sns_topic` | The notification "mailbox" (topic) |
| `aws_sns_topic_policy` | Permission policy — who can send to this topic |
| `data aws_caller_identity` | Data source: gets your AWS account ID |
| `aws_sns_topic_subscription` | Email subscriptions (one per address, via `for_each`) |

---

## 🔍 What is SNS?

SNS = Simple Notification Service.
It is a **pub/sub messaging service** — publishers send messages, subscribers receive them.

```
Publisher:  CloudWatch Alarm triggers (e.g., EC2 CPU > 80%)
                │
                ▼
           SNS Topic  (like a mailbox or bulletin board)
                │
        ┌───────┴───────┐
        ▼               ▼
   Email subscriber   Lambda function
  ops@example.com     (auto-remediation)
```

**In this project:**
- CloudWatch alarms **publish** to the SNS topic when something goes wrong.
- Your email address **subscribes** to receive those alerts.

---

## 🔍 PART 1 — SNS Topic

```hcl
resource "aws_sns_topic" "alerts" {
  name         = "${var.environment}-alerts"
  display_name = "${var.environment} Infrastructure Alerts"

  lifecycle {
    prevent_destroy = false
  }
  ...
}
```

**`name = "${var.environment}-alerts"`**
- The topic name shown in AWS Console → SNS → Topics.
- e.g., `dev-alerts`, `prod-alerts`.
- Each environment has its own topic so dev alarms don't spam prod operators.

**`display_name`**
- Shown as the sender name in notification emails.
- e.g., `"dev Infrastructure Alerts"` appears in email subject lines.
- Without it: emails show the raw topic ARN as sender — confusing.

**`lifecycle { prevent_destroy = false }`**
- We intentionally leave this `false`.
- The environment `main.tf` ensures CloudWatch (which references this topic)
  is destroyed BEFORE SNS via `depends_on`.
- So the destroy order is safe without needing `prevent_destroy`.

---

## 🔍 PART 2 — Data Source: `aws_caller_identity`

```hcl
data "aws_caller_identity" "current" {}
```

This data source asks AWS: "What AWS account am I running in right now?"

**Why do we need the account ID?**
The SNS topic policy needs to reference the account ID to:
1. Restrict CloudWatch to only publish from YOUR account (not any AWS account).
2. Grant the account root full access for subscription management.

```
❌ WITHOUT this data source:
  You'd hardcode: "aws:SourceAccount": "123456789012"
  Works but breaks if you share this code with another account.
  Maintenance burden — easy to forget to update.

✅ WITH this data source:
  "aws:SourceAccount": data.aws_caller_identity.current.account_id
  Works in any AWS account automatically.
  Zero maintenance.
```

**`data.aws_caller_identity.current.account_id`** — returns your 12-digit account ID.

---

## 🔍 PART 3 — SNS Topic Policy

```hcl
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
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
```

**What is a topic policy?**
Resource-based policy (like an S3 bucket policy) that controls
who can perform actions ON the SNS topic.

**Without this policy:**
CloudWatch alarms fire but silently fail to publish to SNS.
You see "ALARM" state in CloudWatch but receive no email. Very confusing to debug.

**`jsonencode({...})`**
- Converts HCL map/list to a JSON string that AWS expects.
- Much more readable than a raw JSON heredoc.

**Statement 1 — Allow CloudWatch to publish:**

```hcl
Principal = { Service = "cloudwatch.amazonaws.com" }
Action    = "SNS:Publish"
Condition = { StringEquals = { "aws:SourceAccount" = account_id } }
```
- `Principal: Service: cloudwatch.amazonaws.com` — only the CloudWatch service.
- `Action: SNS:Publish` — only the publish action (not subscribe, delete, etc.).
- `Condition: aws:SourceAccount` — only CloudWatch in YOUR account.
  Without this condition: CloudWatch from ANY AWS account could publish to your topic.
  This prevents your alerts from being spammed by strangers.

**Statement 2 — Allow owner account full access:**

```hcl
Principal = { AWS = "arn:aws:iam::ACCOUNT_ID:root" }
Action    = "SNS:*"
```
- Account root can do anything: subscribe emails, view messages, delete topic, etc.
- Needed for Terraform itself to manage subscriptions.

---

## 🔍 PART 4 — Email Subscriptions

```hcl
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value

  depends_on = [aws_sns_topic_policy.alerts]
}
```

**`for_each = toset(var.alert_email_addresses)`**

```
INPUT variable:
alert_email_addresses = ["ops@example.com", "dev@example.com"]

toset() converts list → set:
{ "ops@example.com", "dev@example.com" }

for_each creates:
  aws_sns_topic_subscription.email["ops@example.com"]
  aws_sns_topic_subscription.email["dev@example.com"]
```

Each email address gets its own subscription resource.
Removing one email from the list → only that subscription is deleted.
Other subscriptions are untouched.

**`protocol = "email"`**
- SNS supports many protocols: `email`, `email-json`, `sms`, `http`, `lambda`, `sqs`.
- `"email"` sends a plain text email to the endpoint.

**`endpoint = each.value`** — the email address.

**`depends_on = [aws_sns_topic_policy.alerts]`**
- The policy must be applied before subscriptions are created.
- If subscriptions are created before the policy, the confirmation email is sent
  but when the subscriber clicks confirm, the policy may not yet allow it.
- Wait for policy → then add subscriptions. Safe.

**⚠️ Important: Confirmation Required**
AWS sends a confirmation email to each address.
The recipient MUST click "Confirm subscription" in that email.
Until confirmed, they won't receive alerts.

```
After terraform apply:
  1. Check your inbox for "AWS Notification — Subscription Confirmation"
  2. Click the "Confirm subscription" link
  3. Now you'll receive CloudWatch alarm notifications
```

---

## 📤 Key Output

```hcl
output "topic_arn" {
  value = aws_sns_topic.alerts.arn
}
```

This ARN is passed to the CloudWatch module:
```hcl
module "cloudwatch" {
  alarm_sns_arn = module.sns.topic_arn
}
```

---

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `data aws_caller_identity` | topic policy | Dynamic account ID — no hardcoding |
| `jsonencode()` | topic policy | Clean HCL → JSON conversion |
| `for_each` + `toset()` | email subscriptions | One resource per email address |
| `depends_on` | subscriptions | Policy must exist before subscriptions |
| `lifecycle` | SNS topic | Prevent accidental deletion awareness |
