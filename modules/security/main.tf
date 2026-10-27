# ==============================================================================
# MODULE: Security Groups
# PURPOSE: Define firewall rules for EC2, ALB, RDS, and EKS.
# CONCEPTS: for_each on inline rules, dynamic blocks, lifecycle
# ==============================================================================

# ------------------------------------------------------------------------------
# SECURITY GROUP: EC2 / App Server
# Allows: SSH (22), HTTPS (443), Jenkins (8080) inbound
#         All outbound traffic
# ------------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.environment}-ec2-sg"
  description = "Security group for EC2 app servers"
  vpc_id      = var.vpc_id

  # CONCEPT: dynamic block
  # Instead of writing one ingress block per port, we loop over a variable list.
  # This makes the module reusable: just change the variable.
  dynamic "ingress" {
    for_each = var.ec2_ingress_rules   # list of { port, protocol, cidr, description }
    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  # Outbound: allow everything (EC2 needs to reach the internet to install packages)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # "-1" means ALL protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  # CONCEPT: lifecycle
  # Create the new SG before destroying the old one so instances never
  # have a period with no security group attached.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-sg"
  })
}

# ------------------------------------------------------------------------------
# SECURITY GROUP: RDS (Database)
# Only allows inbound from the EC2 security group on the DB port.
# Never expose your database directly to the internet!
# ------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS — only EC2 SG allowed inbound"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL/Aurora from EC2 security group"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id] # Reference another SG, not a CIDR
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-rds-sg"
  })
}

# ------------------------------------------------------------------------------
# SECURITY GROUP: EKS Cluster (control plane)
# ------------------------------------------------------------------------------
resource "aws_security_group" "eks_cluster" {
  name        = "${var.environment}-eks-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = var.vpc_id

  # HTTPS from worker nodes (kubelet ↔ API server communication)
  ingress {
    description     = "Kubernetes API from worker nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eks-cluster-sg"
  })
}

# ------------------------------------------------------------------------------
# SECURITY GROUP: EKS Nodes (worker nodes)
# ------------------------------------------------------------------------------
resource "aws_security_group" "eks_nodes" {
  name        = "${var.environment}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Workers need to talk to each other (pod-to-pod traffic)
  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true   # "self" = this security group itself
  }

  # API server sends commands back to kubelets on port 10250
  ingress {
    description     = "Control plane to node kubelet"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eks-nodes-sg"
  })
}
