# ==============================================================================
# MODULE: Compute (EC2 Instance)
# PURPOSE: Launch an EC2 instance with a key pair, security group, and
#          user data script that installs Jenkins, Docker, and Terraform.
# CONCEPTS: resource, data source, user_data, key_name, count
# ==============================================================================

# ------------------------------------------------------------------------------
# DATA SOURCE: Look up the latest Ubuntu 22.04 AMI automatically
# This avoids hard-coding an AMI ID that changes per region.
# ------------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# RESOURCE: aws_key_pair
# Creates an SSH key pair in AWS using a PUBLIC key you provide.
# The private key stays on your laptop — AWS never sees it.
# ------------------------------------------------------------------------------
resource "aws_key_pair" "devops" {
  key_name   = var.key_name               # e.g. "devops"
  public_key = file(var.public_key_path)  # path to ~/.ssh/id_rsa.pub

  tags = merge(var.common_tags, {
    Name = "${var.environment}-devops-key"
  })
}

# ------------------------------------------------------------------------------
# RESOURCE: aws_instance
# The actual EC2 virtual machine.
# user_data runs the install script ONCE on first boot.
# ------------------------------------------------------------------------------
resource "aws_instance" "app_server" {
  # How many instances to create — driven by variable (default 1)
  # CONCEPT: count — create N identical resources
  count = var.instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.devops.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.security_group_id]

  # IAM instance profile allows EC2 → SSM Session Manager (no SSH needed)
  iam_instance_profile = var.iam_instance_profile

  # Pass the install script as user data (base64-encoded automatically by TF)
  user_data = file("${path.module}/scripts/install.sh")

  # Root EBS volume
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size # GB
    delete_on_termination = true                 # cleaned up when instance terminates
    encrypted             = true                 # always encrypt at rest
  }

  # CONCEPT: lifecycle — prevent accidental replacement of a running server
  lifecycle {
    create_before_destroy = true   # spin up new one before killing old one
    ignore_changes        = [ami]  # don't replace instance just because a new AMI dropped
  }

  tags = merge(var.common_tags, {
    # When count > 1, each instance gets a unique name like "dev-app-server-0"
    Name = "${var.environment}-app-server-${count.index}"
    Role = "app-server"
  })
}

# ------------------------------------------------------------------------------
# RESOURCE: aws_eip  (Elastic IP)
# Static public IP attached to each instance.
# CONCEPT: count.index — matches EIP to the correct instance
# ------------------------------------------------------------------------------
resource "aws_eip" "app_server" {
  count    = var.instance_count
  instance = aws_instance.app_server[count.index].id
  domain   = "vpc"

  # CONCEPT: depends_on — explicit dependency when Terraform can't detect it
  # The internet gateway must exist before an EIP is useful
  depends_on = [var.internet_gateway_id]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-eip-${count.index}"
  })
}
