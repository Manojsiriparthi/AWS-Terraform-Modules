# ==============================================================================
# MODULE: Networking
# PURPOSE: Create a full VPC with:
#   - 2 public subnets  (internet-facing, ELB / bastion / EC2)
#   - 2 private subnets (app servers, RDS, EKS nodes)
#   - Internet Gateway  (public traffic in/out)
#   - NAT Gateway       (private subnets can reach the internet, not vice versa)
#   - Route tables      (wired to the correct subnets)
# CONCEPTS: for_each, locals, depends_on, data source
# ==============================================================================

# ------------------------------------------------------------------------------
# LOCAL VALUES
# Locals let you compute derived values once and reuse them.
# CONCEPT: locals block
# ------------------------------------------------------------------------------
locals {
  # Build a map of public subnets: { "public-0" = { cidr=.., az=.. }, ... }
  public_subnets_map = {
    for idx, cidr in var.public_subnet_cidrs :
    "public-${idx}" => {
      cidr = cidr
      az   = element(data.aws_availability_zones.available.names, idx)
    }
  }

  # Build a map of private subnets the same way
  private_subnets_map = {
    for idx, cidr in var.private_subnet_cidrs :
    "private-${idx}" => {
      cidr = cidr
      az   = element(data.aws_availability_zones.available.names, idx)
    }
  }
}

# ------------------------------------------------------------------------------
# DATA SOURCE: Fetch available AZs in the current region dynamically
# ------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------------------
# VPC
# The private network that contains all our AWS resources.
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # Required for EKS and many AWS services
  enable_dns_hostnames = true   # Instances get human-readable DNS names

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpc"
  })
}

# ------------------------------------------------------------------------------
# INTERNET GATEWAY
# Allows resources in public subnets to communicate with the internet.
# One per VPC.
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-igw"
  })
}

# ------------------------------------------------------------------------------
# PUBLIC SUBNETS
# CONCEPT: for_each — create one subnet per entry in local.public_subnets_map
# each.key = "public-0", each.value = { cidr=.., az=.. }
# ------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets_map

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true   # instances launched here get a public IP

  tags = merge(var.common_tags, {
    Name                     = "${var.environment}-${each.key}-subnet"
    "kubernetes.io/role/elb" = "1" # Required tag for EKS to place load balancers here
  })
}

# ------------------------------------------------------------------------------
# PRIVATE SUBNETS
# No direct internet access — traffic goes through NAT Gateway.
# ------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  for_each = local.private_subnets_map

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(var.common_tags, {
    Name                              = "${var.environment}-${each.key}-subnet"
    "kubernetes.io/role/internal-elb" = "1" # Required for EKS internal load balancers
  })
}

# ------------------------------------------------------------------------------
# ELASTIC IP for NAT GATEWAY
# The NAT Gateway needs a static public IP.
# ------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  # The IGW must exist before the EIP is usable in a VPC
  depends_on = [aws_internet_gateway.main]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-nat-eip"
  })
}

# ------------------------------------------------------------------------------
# NAT GATEWAY
# Lives in a PUBLIC subnet. Private subnets route outbound traffic through it.
# Note: Only one NAT GW here (cost-efficient for dev/test).
#       For production, add one per AZ for high availability.
# ------------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  # Place the NAT GW in the FIRST public subnet
  subnet_id = values(aws_subnet.public)[0].id

  # NAT GW needs both the EIP and the IGW
  depends_on = [aws_internet_gateway.main, aws_eip.nat]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-nat-gw"
  })
}

# ------------------------------------------------------------------------------
# ROUTE TABLE — PUBLIC
# Route 0.0.0.0/0 → Internet Gateway (all outbound internet traffic)
# ------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-public-rt"
  })
}

# Associate every public subnet with the public route table
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# ROUTE TABLE — PRIVATE
# Route 0.0.0.0/0 → NAT Gateway (outbound only, no inbound from internet)
# ------------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-private-rt"
  })
}

# Associate every private subnet with the private route table
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
