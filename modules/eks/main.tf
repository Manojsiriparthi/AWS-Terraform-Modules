# ==============================================================================
# MODULE: EKS (Elastic Kubernetes Service)
# PURPOSE: Create a managed Kubernetes cluster with:
#   - EKS Control Plane
#   - Managed Node Group (2 worker nodes)
#   - Add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI Driver
# CONCEPTS: depends_on, for_each on add-ons, lifecycle
# ==============================================================================

# ------------------------------------------------------------------------------
# EKS CLUSTER (Control Plane)
# AWS manages the master nodes — you only manage the worker nodes.
# ------------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-eks-cluster"
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version   # e.g. "1.29"

  vpc_config {
    subnet_ids              = var.private_subnet_ids         # nodes run in private subnets
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_private_access = true    # kubeconfig can use private endpoint
    endpoint_public_access  = var.public_access_enabled      # set false in strict prod
  }

  # Enable control plane logs for debugging and auditing
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # CONCEPT: depends_on
  # The cluster needs the IAM role policy attachments to be ready first.
  # Even though we pass role_arn, Terraform can't infer this dependency automatically.
  depends_on = [var.cluster_role_policy_dependency]

  # CONCEPT: lifecycle — prevent replace during minor updates
  lifecycle {
    ignore_changes = [
      vpc_config[0].security_group_ids,  # AWS may add its own SG
    ]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eks-cluster"
  })
}

# ------------------------------------------------------------------------------
# EKS MANAGED NODE GROUP
# AWS manages the EC2 worker nodes (patching, scaling, replacement).
# ------------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-node-group"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids   # nodes in private subnets

  # AMI type: Amazon Linux 2 optimised for EKS
  ami_type       = "AL2_x86_64"
  instance_types = [var.node_instance_type]
  disk_size      = var.node_disk_size   # GB

  scaling_config {
    desired_size = var.node_desired_count   # 2 nodes by default
    min_size     = var.node_min_count       # 1 minimum
    max_size     = var.node_max_count       # 4 maximum
  }

  update_config {
    max_unavailable = 1   # rolling update: at most 1 node down at a time
  }

  # CONCEPT: depends_on — nodes need the cluster to exist first
  depends_on = [
    aws_eks_cluster.main,
    var.node_role_policy_dependency,
  ]

  # CONCEPT: lifecycle — ignore desired_size so auto-scaling changes don't
  # cause Terraform to revert the count on next apply
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eks-node-group"
  })
}

# ------------------------------------------------------------------------------
# EKS ADD-ONS
# CONCEPT: for_each — deploy multiple add-ons from a single resource block
# Add-ons are AWS-managed plugins for networking, DNS, and storage.
# ------------------------------------------------------------------------------
resource "aws_eks_addon" "addons" {
  for_each = var.eks_addons   # map: { "coredns" = { version="v1.x.x" }, ... }

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = each.key
  addon_version            = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Add-ons need the node group to be READY (for coredns scheduling)
  depends_on = [aws_eks_node_group.main]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${each.key}-addon"
  })
}
