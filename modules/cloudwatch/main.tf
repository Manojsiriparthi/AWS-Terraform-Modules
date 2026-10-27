# ==============================================================================
# MODULE: CloudWatch
# PURPOSE: Create monitoring dashboards and alarms for:
#   - EKS Cluster
#   - EC2 Instance
#   - Networking (NAT Gateway, VPC flow logs)
# CONCEPTS: for_each on alarms, locals, jsonencode for dashboard JSON
# ==============================================================================

locals {
  # Prefix used in all resource names
  prefix = "${var.environment}-cw"
}

# ==============================================================================
# DASHBOARDS (3 total)
# CloudWatch dashboards are defined as JSON. jsonencode() keeps them readable.
# ==============================================================================

# ------------------------------------------------------------------------------
# DASHBOARD 1: EC2
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "ec2" {
  dashboard_name = "${local.prefix}-ec2"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
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
      },
      {
        type   = "metric"
        x      = 12; y = 0; width = 12; height = 6
        properties = {
          title  = "EC2 Network In/Out"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "NetworkIn",  "InstanceId", var.ec2_instance_id],
            ["AWS/EC2", "NetworkOut", "InstanceId", var.ec2_instance_id]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0; y = 6; width = 12; height = 6
        properties = {
          title  = "EC2 Disk Read/Write Ops"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "DiskReadOps",  "InstanceId", var.ec2_instance_id],
            ["AWS/EC2", "DiskWriteOps", "InstanceId", var.ec2_instance_id]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# DASHBOARD 2: EKS Cluster
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "eks" {
  dashboard_name = "${local.prefix}-eks-cluster"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "EKS Node CPU"
          region = var.aws_region
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.eks_cluster_name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12; y = 0; width = 12; height = 6
        properties = {
          title  = "EKS Node Memory"
          region = var.aws_region
          metrics = [
            ["ContainerInsights", "node_memory_utilization", "ClusterName", var.eks_cluster_name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0; y = 6; width = 12; height = 6
        properties = {
          title  = "EKS Pod Count"
          region = var.aws_region
          metrics = [
            ["ContainerInsights", "pod_number_of_running_pods", "ClusterName", var.eks_cluster_name]
          ]
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# DASHBOARD 3: Networking (NAT Gateway traffic)
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "networking" {
  dashboard_name = "${local.prefix}-networking"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "NAT Gateway Bytes In/Out"
          region = var.aws_region
          metrics = [
            ["AWS/NATGateway", "BytesInFromDestination", "NatGatewayId", var.nat_gateway_id],
            ["AWS/NATGateway", "BytesOutToSource",       "NatGatewayId", var.nat_gateway_id]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12; y = 0; width = 12; height = 6
        properties = {
          title  = "NAT Gateway Connections"
          region = var.aws_region
          metrics = [
            ["AWS/NATGateway", "ActiveConnectionCount", "NatGatewayId", var.nat_gateway_id]
          ]
          period = 300
          stat   = "Maximum"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ==============================================================================
# CLOUDWATCH ALARMS (10 total)
# CONCEPT: for_each — define all alarms in a variable map, deploy with one block
# ==============================================================================

# Build a local map of all alarm definitions
locals {
  alarms = {

    # ---- EC2 Alarms ----
    ec2_cpu_high = {
      alarm_name          = "${local.prefix}-ec2-cpu-high"
      alarm_description   = "EC2 CPU utilization > 80% for 5 minutes"
      namespace           = "AWS/EC2"
      metric_name         = "CPUUtilization"
      dimensions          = { InstanceId = var.ec2_instance_id }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 2
      period              = 300
      statistic           = "Average"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    ec2_status_check_failed = {
      alarm_name          = "${local.prefix}-ec2-status-check"
      alarm_description   = "EC2 status check failed (instance or system check)"
      namespace           = "AWS/EC2"
      metric_name         = "StatusCheckFailed"
      dimensions          = { InstanceId = var.ec2_instance_id }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      evaluation_periods  = 1
      period              = 60
      statistic           = "Maximum"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    ec2_network_in_high = {
      alarm_name          = "${local.prefix}-ec2-network-in"
      alarm_description   = "EC2 inbound network > 100MB/5min (possible traffic spike)"
      namespace           = "AWS/EC2"
      metric_name         = "NetworkIn"
      dimensions          = { InstanceId = var.ec2_instance_id }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 104857600  # 100 MB in bytes
      evaluation_periods  = 1
      period              = 300
      statistic           = "Sum"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    # ---- EKS Alarms ----
    eks_node_cpu_high = {
      alarm_name          = "${local.prefix}-eks-node-cpu"
      alarm_description   = "EKS node CPU > 85%"
      namespace           = "ContainerInsights"
      metric_name         = "node_cpu_utilization"
      dimensions          = { ClusterName = var.eks_cluster_name }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 85
      evaluation_periods  = 3
      period              = 60
      statistic           = "Average"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    eks_node_memory_high = {
      alarm_name          = "${local.prefix}-eks-node-memory"
      alarm_description   = "EKS node memory > 85%"
      namespace           = "ContainerInsights"
      metric_name         = "node_memory_utilization"
      dimensions          = { ClusterName = var.eks_cluster_name }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 85
      evaluation_periods  = 3
      period              = 60
      statistic           = "Average"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    eks_pod_count_low = {
      alarm_name          = "${local.prefix}-eks-pod-count"
      alarm_description   = "EKS running pods < 1 (possible cluster crash)"
      namespace           = "ContainerInsights"
      metric_name         = "pod_number_of_running_pods"
      dimensions          = { ClusterName = var.eks_cluster_name }
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      evaluation_periods  = 2
      period              = 60
      statistic           = "Sum"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    # ---- RDS Alarms ----
    rds_cpu_high = {
      alarm_name          = "${local.prefix}-rds-cpu"
      alarm_description   = "RDS CPU > 75%"
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      dimensions          = { DBInstanceIdentifier = var.rds_instance_id }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 75
      evaluation_periods  = 2
      period              = 300
      statistic           = "Average"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    rds_free_storage_low = {
      alarm_name          = "${local.prefix}-rds-storage"
      alarm_description   = "RDS free storage < 5 GB"
      namespace           = "AWS/RDS"
      metric_name         = "FreeStorageSpace"
      dimensions          = { DBInstanceIdentifier = var.rds_instance_id }
      comparison_operator = "LessThanThreshold"
      threshold           = 5368709120  # 5 GB in bytes
      evaluation_periods  = 1
      period              = 300
      statistic           = "Minimum"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    # ---- Networking Alarms ----
    nat_error_port_alloc = {
      alarm_name          = "${local.prefix}-nat-port-alloc-error"
      alarm_description   = "NAT Gateway ran out of ports — scale up or investigate"
      namespace           = "AWS/NATGateway"
      metric_name         = "ErrorPortAllocation"
      dimensions          = { NatGatewayId = var.nat_gateway_id }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 0
      evaluation_periods  = 1
      period              = 60
      statistic           = "Sum"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }

    nat_packet_drop = {
      alarm_name          = "${local.prefix}-nat-packet-drop"
      alarm_description   = "NAT Gateway is dropping packets"
      namespace           = "AWS/NATGateway"
      metric_name         = "PacketsDropCount"
      dimensions          = { NatGatewayId = var.nat_gateway_id }
      comparison_operator = "GreaterThanThreshold"
      threshold           = 100
      evaluation_periods  = 2
      period              = 300
      statistic           = "Sum"
      alarm_actions       = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
    }
  }
}

# CONCEPT: for_each — one aws_cloudwatch_metric_alarm resource for all 10 alarms
resource "aws_cloudwatch_metric_alarm" "alarms" {
  for_each = local.alarms

  alarm_name          = each.value.alarm_name
  alarm_description   = each.value.alarm_description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  period              = each.value.period
  statistic           = each.value.statistic
  alarm_actions       = each.value.alarm_actions
  treat_missing_data  = "notBreaching"   # don't alarm when metric is missing

  tags = merge(var.common_tags, {
    Name = each.value.alarm_name
  })
}
