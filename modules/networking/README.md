# 🌐 Module: Networking (VPC)

> **Spoon-feeding guide — every single line explained.**
> This module is the FOUNDATION. Every other module depends on what is created here.

---

## 📦 What Does This Module Create?

| Resource | What it is |
|----------|-----------|
| `data aws_availability_zones` | Reads available AZs in the region automatically |
| `locals` | Builds subnet config maps from your CIDR lists |
| `aws_vpc` | The private network that wraps all your AWS resources |
| `aws_internet_gateway` | The door to the internet for public subnets |
| `aws_subnet` (public ×2) | Subnets where EC2, load balancers live — have internet access |
| `aws_subnet` (private ×2) | Subnets where RDS, EKS nodes live — no direct internet |
| `aws_eip` | Static public IP for the NAT Gateway |
| `aws_nat_gateway` | Lets private subnets reach the internet (outbound only) |
| `aws_route_table` (public) | Routing rule: public traffic → Internet Gateway |
| `aws_route_table` (private) | Routing rule: private traffic → NAT Gateway |
| `aws_route_table_association` | Wires each subnet to the correct route table |

---

## 🗺️ Architecture Diagram

```
                        INTERNET
                           │
                    ┌──────▼──────┐
                    │   Internet  │
                    │   Gateway   │
                    └──────┬──────┘
                           │
              ┌────────────▼────────────┐
              │         VPC             │
              │    10.0.0.0/16          │
              │                         │
   ┌──────────┴──────┐   ┌──────────────┴──────┐
   │  Public Subnet  │   │   Public Subnet      │
   │  10.0.1.0/24    │   │   10.0.2.0/24        │
   │  AZ: us-east-1a │   │   AZ: us-east-1b     │
   │  EC2, Jenkins   │   │   Load Balancer      │
   └────────┬────────┘   └──────────────────────┘
            │ NAT Gateway (outbound only)
   ┌────────▼────────┐   ┌──────────────────────┐
   │  Private Subnet │   │   Private Subnet     │
   │  10.0.10.0/24   │   │   10.0.11.0/24       │
   │  AZ: us-east-1a │   │   AZ: us-east-1b     │
   │  RDS, EKS Nodes │   │   RDS Replica        │
   └─────────────────┘   └──────────────────────┘
```

---

## 🔍 PART 1 — What is a VPC?

VPC = Virtual Private Cloud. It is your **own private network inside AWS**.

Think of it like renting a floor in an office building:
- The building = AWS infrastructure (shared with everyone)
- Your floor = VPC (only YOUR resources live here)
- Rooms on your floor = subnets
- The front door = Internet Gateway
- A back delivery door = NAT Gateway

**Without a VPC:**
All your resources would be on a flat public network — anyone on the internet
could potentially reach your database. No isolation, no security.

**With a VPC:**
You control every bit of network access. Database lives in a private subnet.
Only EC2 (in the same VPC) can reach it.

---

## 🔍 PART 2 — Data Source: `aws_availability_zones`

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

**What is it?**
A data source that asks AWS: "Which availability zones are currently up in this region?"

**Why not hardcode AZ names?**

```hcl
# ❌ WITHOUT data source — hardcoded:
availability_zone = "us-east-1a"
# Problem 1: You change region to eu-west-1 — "us-east-1a" doesn't exist there. CRASH.
# Problem 2: AWS occasionally retires AZs. Your code breaks silently.
# Problem 3: Not all accounts have access to all AZs (capacity reservations).

# ✅ WITH data source — dynamic:
availability_zone = data.aws_availability_zones.available.names[0]
# Always correct for whatever region you're deploying to.
# Works in us-east-1, eu-west-1, ap-southeast-1 — any region.
```

`state = "available"` — only return AZs that are currently active, not impaired or unavailable.

---

## 🔍 PART 3 — Locals Block

```hcl
locals {
  public_subnets_map = {
    for idx, cidr in var.public_subnet_cidrs :
    "public-${idx}" => {
      cidr = cidr
      az   = element(data.aws_availability_zones.available.names, idx)
    }
  }
}
```

**What is a `locals` block?**
Locals are computed values you define once and reuse. Like a variable but calculated,
not just stored.

**What does this `for` expression do?**
It transforms a plain list into a map. `for_each` needs a map (not a list) to work.

```
INPUT (list):
var.public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

OUTPUT (map):
{
  "public-0" = { cidr = "10.0.1.0/24", az = "us-east-1a" }
  "public-1" = { cidr = "10.0.2.0/24", az = "us-east-1b" }
}
```

`element(list, index)` — picks item at `index` from a list, wrapping around if needed.
So index 0 → first AZ, index 1 → second AZ. Each subnet goes into a different AZ
for high availability.

**Why build a map?**
`for_each` requires a map or set — not a list. If we used `count` with a list,
removing one CIDR would reindex all subnets and Terraform would destroy/recreate them.
With a named map key like `"public-0"`, removing it only deletes that one subnet.

---

## 🔍 PART 4 — VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  ...
}
```

**`cidr_block = var.vpc_cidr`** — default `10.0.0.0/16`
- CIDR = Classless Inter-Domain Routing. Defines the IP address range for the VPC.
- `10.0.0.0/16` = 65,536 IP addresses available (10.0.0.0 → 10.0.255.255)
- All subnets must be smaller ranges WITHIN this block.
- Each environment uses a different range (dev=10.0, test=10.1, prod=10.2)
  so they don't overlap if ever connected via VPC peering.

**`enable_dns_support = true`**
- Allows AWS DNS resolution inside the VPC.
- Required for EKS (pods need DNS to find each other and AWS services).
- Without this: services can't resolve `rds.amazonaws.com` or each other's hostnames.

**`enable_dns_hostnames = true`**
- Gives each instance a human-readable DNS name like:
  `ec2-54-123-45-67.compute-1.amazonaws.com`
- Without this: instances only have raw IP addresses — harder to debug.

---

## 🔍 PART 5 — Internet Gateway

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  ...
}
```

**What is an Internet Gateway?**
The IGW is the door between your VPC and the public internet.

```
WITHOUT Internet Gateway:
  EC2 in public subnet → can't reach google.com
  Nothing can reach your EC2 either
  Your VPC is completely isolated — a closed room

WITH Internet Gateway:
  EC2 in public subnet → can reach google.com (via route table)
  You can SSH into EC2 from your laptop
  Jenkins can pull code from GitHub
```

**Rules:**
- One IGW per VPC
- Attach it to the VPC (`vpc_id = aws_vpc.main.id`)
- Then create a route table rule pointing `0.0.0.0/0` → IGW (done in Part 8)
- Only subnets whose route table points to the IGW are "public"

---

## 🔍 PART 6 — Public Subnets

```hcl
resource "aws_subnet" "public" {
  for_each = local.public_subnets_map

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name                     = "${var.environment}-${each.key}-subnet"
    "kubernetes.io/role/elb" = "1"
  })
}
```

**`for_each = local.public_subnets_map`**
- Creates one subnet per entry in the map.
- `each.key` = `"public-0"` or `"public-1"`
- `each.value` = `{ cidr = "10.0.1.0/24", az = "us-east-1a" }`

**`vpc_id = aws_vpc.main.id`**
- Place this subnet inside our VPC. Terraform creates the VPC first (implicit dependency).

**`cidr_block = each.value.cidr`**
- The IP range for this specific subnet.
- `10.0.1.0/24` = 256 addresses (10.0.1.0 → 10.0.1.255)
- Must be a subset of the VPC CIDR (`10.0.0.0/16`).

**`availability_zone = each.value.az`**
- Which physical data centre this subnet lives in.
- 2 subnets in 2 different AZs = if one data centre has a power outage, the other is still up.

**`map_public_ip_on_launch = true`**
- Every EC2 instance launched into this subnet automatically gets a public IP.

```
WITHOUT this: EC2 starts with only a private IP. No public access.
              You'd need to manually assign an EIP to every instance.
WITH this:    EC2 automatically gets a public IP on launch. Simpler.
              (We also add an EIP in the compute module for a static IP)
```

**`"kubernetes.io/role/elb" = "1"`**
- This special tag tells EKS: "put internet-facing load balancers in this subnet."
- Without this tag, when you create a Kubernetes LoadBalancer service, EKS
  doesn't know where to place it and the service stays in `<pending>` forever.

---

## 🔍 PART 7 — Private Subnets

```hcl
resource "aws_subnet" "private" {
  for_each = local.private_subnets_map

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(var.common_tags, {
    "kubernetes.io/role/internal-elb" = "1"
  })
}
```

**Same structure as public subnets, key differences:**
- No `map_public_ip_on_launch` — private instances do NOT get public IPs.
  They are reachable only from inside the VPC.
- `"kubernetes.io/role/internal-elb" = "1"` — tells EKS to put
  internal-only load balancers here (not exposed to the internet).

**What lives in private subnets?**
- RDS database — should NEVER be publicly accessible
- EKS worker nodes — receive traffic only through load balancers, not directly
- Lambda functions, ElastiCache, etc.

---

## 🔍 PART 8 — EIP for NAT Gateway

```hcl
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
  ...
}
```

The NAT Gateway needs a static public IP address.
This EIP is that static IP.

**`depends_on = [aws_internet_gateway.main]`**
- The IGW must exist before the EIP can be associated in the VPC context.
- Terraform can't detect this automatically because there's no direct
  reference between EIP and IGW in the code — must declare it explicitly.

---

## 🔍 PART 9 — NAT Gateway

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  depends_on    = [aws_internet_gateway.main, aws_eip.nat]
  ...
}
```

**What is a NAT Gateway?**

NAT = Network Address Translation. It's a one-way door.

```
WITHOUT NAT Gateway:
  Private subnet instance needs to install Docker.
  It tries to reach hub.docker.com...
  No route to the internet. Package install fails.
  Your EKS nodes can't pull container images. Nothing works.

WITH NAT Gateway:
  Private instance → NAT Gateway → Internet Gateway → Internet
  Internet → NAT Gateway blocks unsolicited inbound traffic
  Private instances stay private but can reach the internet outbound.
```

**`allocation_id = aws_eip.nat.id`** — attach the static EIP to this NAT GW.

**`subnet_id = values(aws_subnet.public)[0].id`**
- NAT Gateway MUST live in a PUBLIC subnet (it needs IGW access to reach the internet).
- `values(aws_subnet.public)` converts the `for_each` map to a list of subnet objects.
- `[0]` picks the first one.

**`depends_on = [aws_internet_gateway.main, aws_eip.nat]`**
- Both the IGW and the EIP must exist before the NAT GW can be created.
- Without IGW: NAT GW is created but has no path to the internet — useless.
- Without EIP: NAT GW creation fails — it requires an IP allocation.

---

## 🔍 PART 10 — Route Tables

**What is a Route Table?**
A route table is a set of rules that tells network traffic "where to go."

Every subnet must be associated with a route table. Traffic from resources
in the subnet follows these rules to decide where packets go.

### Public Route Table

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
```

**`cidr_block = "0.0.0.0/0"`** — means "ALL traffic" (any destination IP).

**`gateway_id = aws_internet_gateway.main.id`** — send that traffic to the IGW.

**Reading this rule:**
> "Any traffic going to any IP address → send it to the Internet Gateway."
> This makes subnets associated with this table "public."

### Private Route Table

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```

**Reading this rule:**
> "Any traffic going anywhere → send it to the NAT Gateway."
> NAT GW passes it to the internet. Inbound internet traffic can't
> directly reach the private subnet — only the outbound request gets answered.

### Route Table Associations

```hcl
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
```

- Wires every public subnet to the public route table.
- `for_each = aws_subnet.public` — iterate over the map of public subnets created earlier.
- Without this association, the subnet has no routing rules and traffic goes nowhere.

---

## 📤 Outputs Used by Other Modules

| Output | Used by |
|--------|---------|
| `vpc_id` | security, iam, eks |
| `public_subnet_ids` | compute (EC2 placement) |
| `private_subnet_ids` | eks (node groups), rds (DB placement) |
| `internet_gateway_id` | compute (EIP depends_on) |
| `nat_gateway_id` | cloudwatch (NAT alarm) |
| `public_route_table_id` | reference/debugging |
| `private_route_table_id` | reference/debugging |

---

## 📊 Variables Quick Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | — | dev / test / prod |
| `vpc_cidr` | `10.0.0.0/16` | IP range for the VPC |
| `public_subnet_cidrs` | `["10.0.1.0/24","10.0.2.0/24"]` | 2 public subnets |
| `private_subnet_cidrs` | `["10.0.10.0/24","10.0.11.0/24"]` | 2 private subnets |
| `common_tags` | `{}` | Tags applied to every resource |

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `data` source | AZ lookup | Never hardcode AZ names |
| `locals` + `for` expression | Subnet map building | Convert list → map for `for_each` |
| `for_each` | Subnets, route table associations | Named resources, safe to remove one |
| `element()` function | AZ assignment | Spread subnets across AZs |
| `values()` function | NAT GW subnet | Convert for_each map to list |
| `depends_on` | EIP, NAT GW | Explicit ordering where TF can't infer |
