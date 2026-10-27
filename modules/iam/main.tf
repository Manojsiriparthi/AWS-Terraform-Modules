# ==============================================================================
# MODULE: IAM
# PURPOSE: Create all IAM roles and policies needed by:
#   1. EC2  — SSM Session Manager, S3, Secrets Manager (RDS password), CloudWatch
#   2. EKS Cluster — control plane permissions
#   3. EKS Nodes   — worker node permissions
# CONCEPTS: for_each on policies, data sources for policy docs, depends_on
# ==============================================================================

# ==============================================================================
# PART 1: EC2 IAM ROLE
# ==============================================================================

# A "trust policy" defines WHO can assume this role.
# Here: only EC2 instances can assume it.
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-role"
  })
}

# Attach AWS-managed SSM policy — lets you connect to the instance via
# AWS Systems Manager Session Manager (browser-based shell, no port 22 needed)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch agent policy (allows instance to push metrics/logs)
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ------------------------------------------------------------------------------
# INLINE POLICY: EC2 → S3 read/write on our specific bucket
# Using an inline policy document keeps permissions least-privilege.
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_s3_access" {
  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.s3_bucket_arn,          # the bucket itself (for ListBucket)
      "${var.s3_bucket_arn}/*"    # all objects inside the bucket
    ]
  }
}

resource "aws_iam_policy" "ec2_s3" {
  name        = "${var.environment}-ec2-s3-policy"
  description = "Allow EC2 to read/write the app S3 bucket"
  policy      = data.aws_iam_policy_document.ec2_s3_access.json

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_s3.arn

  # CONCEPT: depends_on — the attachment needs both the role and policy to exist
  depends_on = [aws_iam_role.ec2, aws_iam_policy.ec2_s3]
}

# ------------------------------------------------------------------------------
# POLICY ATTACHMENT: EC2 → Secrets Manager (read the RDS password secret)
# The secrets_manager module creates this policy; we attach it here.
# This allows the EC2 instance to fetch the DB password at runtime.
# CONCEPT: depends_on — attachment needs both role and externally-created policy
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ec2_secrets" {
  # Only attach if a policy ARN was provided (it is always provided when
  # the secrets_manager module is used alongside this one).
  count = var.secrets_read_policy_arn != "" ? 1 : 0

  role       = aws_iam_role.ec2.name
  policy_arn = var.secrets_read_policy_arn

  depends_on = [aws_iam_role.ec2]
}

# Instance Profile wraps the role so it can be attached to an EC2 instance
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}

# ==============================================================================
# PART 2: EKS CLUSTER ROLE
# The EKS control plane assumes this role to manage AWS resources.
# ==============================================================================

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.environment}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eks-cluster-role"
  })
}

# CONCEPT: for_each — attach multiple AWS-managed policies in one block
locals {
  eks_cluster_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ])
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  for_each = local.eks_cluster_policies

  role       = aws_iam_role.eks_cluster.name
  policy_arn = each.value   # each.value is the ARN string
}

# ==============================================================================
# PART 3: EKS NODE GROUP ROLE
# Worker nodes assume this role to join the cluster and pull images.
# ==============================================================================

data "aws_iam_policy_document" "eks_nodes_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${var.environment}-eks-nodes-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume_role.json

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eks-nodes-role"
  })
}

locals {
  eks_node_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",       # VPC CNI networking plugin
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",  # pull images from ECR
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",  # push metrics/logs
  ])
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each = local.eks_node_policies

  role       = aws_iam_role.eks_nodes.name
  policy_arn = each.value
}
