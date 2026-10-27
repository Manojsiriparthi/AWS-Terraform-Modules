# 📊 Module: CloudWatch

> **Spoon-feeding guide — every single line explained.**
> Monitoring is not optional in production. This module creates dashboards and alarms for everything.

---

## 📦 What Does This Module Create?

| Resource | What it is |
|----------|-----------|
| `aws_cloudwatch_dashboard.ec2` | Visual dashboard: EC2 CPU, network, disk |
| `aws_cloudwatch_dashboard.eks` | Visual dashboard: EKS node CPU, memory, pod count |
| `aws_cloudwatch_dashboard.networking` | Visual dashboard: NAT Gateway bytes, connections |
| `aws_cloudwatch_metric_alarm` (×10) | Automated alarms that email you when things go wrong |

---

## 🔍 Why CloudWatch?

**Without monitoring:**
```
EC2 CPU hits 100%.
Jenkins builds start failing — jobs are timing out.
No one notices until a developer complains that builds aren't running.
You SSH in, find the server is thrashing.
You have no idea when it started or what caused it.
```

**With CloudWatch:**
```
EC2 CPU hits 80%.
CloudWatch alarm fires → SNS → Email to ops@example.com.
Engineer sees: "EC2 CPU HIGH — dev-app-server-0"
They investigate BEFORE things break.
They scale up or fix the cause within minutes.
```

---

## 🔍 PART 1 — Understanding `locals` in This Module

```hcl
locals {
  prefix = "${var.environment}-cw"
}
```

This local is used as a prefix for every resource name: `dev-cw-ec2`, `dev-cw-eks-cluster`, etc.
Defined once — change the environment and all names update automatically.

---

## 🔍 PART 2 — CloudWatch Dashboards

### What is a CloudWatch Dashboard?

A dashboard is a visual page in the AWS Console (CloudWatch → Dashboards)
showing graphs of metrics. Like a car dashboard — multiple gauges at a glance.

```
WITHOUT dashboards:
  To check EC2 CPU: navigate to EC2 → Instances → select instance → Monitoring tab.
  To check RDS: navigate to RDS → DB instances → select → Monitoring.
  To check EKS: navigate to CloudWatch → Metrics → Container Insights → ...
  Takes 10+ minutes to gather a complete picture.

WITH dashboards:
  Open CloudWatch → Dashboards → dev-cw-ec2
  All EC2 metrics on one screen in 5 seconds.
```

### Dashboard Body: `jsonencode()`

```hcl
resource "aws_cloudwatch_dashboard" "ec2" {
  dashboard_name = "${local.prefix}-ec2"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", var.ec2_instance_id]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      }
    ]
  })
}
```

**`jsonencode({...})`**
- AWS CloudWatch dashboards are defined as JSON.
- `jsonencode()` converts a Terraform HCL map into a valid JSON string.
- Without it: you'd write raw JSON heredoc — hard to read, easy to get a syntax error.

**Dashboard widget fields:**

| Field | Meaning |
|-------|---------|
| `type = "metric"` | Show a metrics graph (not text or alarm) |
| `x, y` | Widget position on the dashboard grid |
| `width = 12` | Half the dashboard width (total = 24) |
| `height = 6` | Height in grid units |
| `title` | Label shown at top of the widget |
| `region` | Which AWS region the metrics come from |
| `metrics` | `[namespace, metric_name, dimension_name, dimension_value]` |
| `period = 300` | Data points every 5 minutes (300 seconds) |
| `stat = "Average"` | Show the average value (vs Maximum, Sum, etc.) |
| `view = "timeSeries"` | Show as a line graph over time |

**The metrics array format:**
```
["AWS/EC2", "CPUUtilization", "InstanceId", "i-0abc123"]
  │           │                │             │
  namespace   metric_name      dimension_k   dimension_v
```

**3 Dashboards created:**
1. **EC2** — CPU utilization, Network In/Out, Disk Read/Write
2. **EKS** — Node CPU, Node Memory, Running pod count (from Container Insights)
3. **Networking** — NAT Gateway bytes in/out, active connection count

---

## 🔍 PART 3 — CloudWatch Alarms (The `for_each` on locals)

### What is a CloudWatch Alarm?

An alarm monitors one metric and performs an action when a threshold is crossed.

```
States:
  OK      — metric is within normal range
  ALARM   — metric crossed the threshold → sends notification
  INSUFFICIENT_DATA — not enough data points yet

Example:
  Metric:    EC2 CPUUtilization
  Threshold: > 80%
  For:       2 consecutive 5-minute periods (10 minutes total)
  Action:    Publish to SNS topic → Email to ops team
```

### The `for_each` on a `locals` map — Why?

Without `for_each`, you'd write 10 separate alarm resources — 10 nearly identical blocks:
```hcl
# ❌ WITHOUT for_each — 10 separate blocks:
resource "aws_cloudwatch_metric_alarm" "ec2_cpu" { ... }
resource "aws_cloudwatch_metric_alarm" "ec2_status" { ... }
resource "aws_cloudwatch_metric_alarm" "ec2_network" { ... }
resource "aws_cloudwatch_metric_alarm" "eks_cpu" { ... }
# ... 6 more
# Adding an 11th alarm = adding a new resource block in code
```

```hcl
# ✅ WITH for_each on local map — 1 resource block for ALL 10:
locals {
  alarms = {
    ec2_cpu_high = { alarm_name = "...", threshold = 80, ... }
    ec2_status   = { alarm_name = "...", threshold = 0,  ... }
    # ... 8 more entries
  }
}

resource "aws_cloudwatch_metric_alarm" "alarms" {
  for_each = local.alarms   # creates 1 resource per map entry

  alarm_name = each.value.alarm_name
  threshold  = each.value.threshold
  # ...
}
# Adding an 11th alarm = adding one entry to the local map. Clean.
```

### Line-by-Line: Each Alarm Field

```hcl
resource "aws_cloudwatch_metric_alarm" "alarms" {
  for_each = local.alarms
```
- `for_each = local.alarms` — creates 10 alarm resources (one per map key).
- `each.key` = alarm identifier like `"ec2_cpu_high"`
- `each.value` = the alarm configuration object

```hcl
  alarm_name        = each.value.alarm_name
```
- Unique name in CloudWatch, e.g. `dev-cw-ec2-cpu-high`.
- Shown in CloudWatch → Alarms list.

```hcl
  alarm_description = each.value.alarm_description
```
- Human-readable explanation. Shown in the alarm detail and in notification emails.
- Always write a good description — it tells the on-call engineer what to do.

```hcl
  namespace   = each.value.namespace
  metric_name = each.value.metric_name
  dimensions  = each.value.dimensions
```
- Together these identify the specific metric.
- `namespace = "AWS/EC2"`, `metric_name = "CPUUtilization"`, `dimensions = { InstanceId = "i-0abc123" }`
- Container Insights metrics use namespace `"ContainerInsights"`.

```hcl
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
```
- Operators: `"GreaterThanThreshold"`, `"LessThanThreshold"`, `"GreaterThanOrEqualToThreshold"`
- `threshold = 80` means alarm when value > 80 (for CPU %).
- For free storage, `threshold = 5368709120` = 5 GB in bytes (CloudWatch uses bytes).

```hcl
  evaluation_periods = each.value.evaluation_periods
  period             = each.value.period
  statistic          = each.value.statistic
```
- `period = 300` — evaluate one data point every 5 minutes.
- `evaluation_periods = 2` — alarm only after 2 CONSECUTIVE periods breach the threshold.
- Why 2 periods? Avoids false alarms on brief CPU spikes.
  A 1-second spike won't alarm. A 10-minute sustained breach will.

```hcl
  alarm_actions      = each.value.alarm_actions
```
- What to do when the alarm fires.
- `alarm_actions = [module.sns.topic_arn]` — publish to the SNS topic → email is sent.
- Empty list `[]` = alarm fires but notifies no one (useful for testing).

```hcl
  treat_missing_data = "notBreaching"
```
- What to do when CloudWatch has no data for the metric.
- Options:
  - `"notBreaching"` — treat missing data as OK (don't alarm). Best for our use case.
  - `"breaching"` — treat missing as a problem (good for heartbeat metrics).
  - `"ignore"` — keep the current alarm state.
  - `"missing"` — report as INSUFFICIENT_DATA state.

---

## 📊 The 10 Alarms — At a Glance

| Alarm | Metric | Threshold | Why |
|-------|--------|-----------|-----|
| `ec2_cpu_high` | EC2 CPU | > 80% for 10 min | Server overloaded |
| `ec2_status_check_failed` | Status check | > 0 | EC2 hardware failure |
| `ec2_network_in_high` | Network In | > 100MB/5min | Traffic spike / DDoS |
| `eks_node_cpu_high` | EKS node CPU | > 85% | Nodes need more capacity |
| `eks_node_memory_high` | EKS node memory | > 85% | Memory pressure on nodes |
| `eks_pod_count_low` | Running pods | < 1 | Cluster crash |
| `rds_cpu_high` | RDS CPU | > 75% | Slow queries / high load |
| `rds_free_storage_low` | RDS free storage | < 5GB | Disk almost full |
| `nat_error_port_alloc` | NAT port error | > 0 | Too many connections |
| `nat_packet_drop` | NAT packet drop | > 100/5min | Network issue |

---

## 📤 Outputs

```hcl
output "alarm_arns" {
  value = { for k, v in aws_cloudwatch_metric_alarm.alarms : k => v.arn }
}
```

- Uses a `for` expression to build a map: `{ "ec2_cpu_high" = "arn:...", ... }`
- Useful for wiring alarms into other systems (PagerDuty, Slack, etc.).

---

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `locals` map | alarm definitions | All 10 alarms defined in one place |
| `for_each` on locals | alarm resource | 1 block creates 10 alarms |
| `jsonencode()` | dashboard body | Clean HCL → JSON conversion |
| `depends_on` | the module | Compute/EKS/RDS must exist before their alarms |
| `for` expression in output | alarm_arns | Build output map from for_each resources |
| Ternary on alarm_actions | all alarms | Empty list if no SNS ARN provided |
