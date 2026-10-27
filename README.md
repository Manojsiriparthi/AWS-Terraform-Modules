# 🚀 AWS Terraform Modules — Complete Learning Guide

> Every concept explained with theory + practical examples + real-world context.

---

## 📚 Table of Contents

1. [What is Terraform?](#1-what-is-terraform)
2. [Terraform Providers](#2-terraform-providers)
3. [terraform init — Deep Dive](#3-terraform-init--deep-dive)
4. [Core Commands](#4-core-commands)
5. [Variables — All Types](#5-variables--all-types)
6. [Outputs](#6-outputs)
7. [Lifecycle Policy](#7-lifecycle-policy)
8. [Locals](#8-locals)
9. [Data Sources](#9-data-sources)
10. [count vs for_each](#10-count-vs-for_each)
11. [Terraform Drift](#11-terraform-drift)
12. [Backends — Local vs Remote](#12-backends--local-vs-remote)
13. [State Locking — Why It Matters](#13-state-locking--why-it-matters)
14. [Workspaces](#14-workspaces)
15. [Modules](#15-modules)
16. [All Terraform Commands — Real World Reference](#16-all-terraform-commands--real-world-reference)
17. [This Repo — Module Map](#17-this-repo--module-map)
18. [Interview Questions](#18-interview-questions)

---

## 1. What is Terraform?

### 📖 Theory

Terraform is an open-source **Infrastructure as Code (IaC)** tool created by **HashiCorp** in **2014**.
It lets you define your cloud infrastructure (servers, networks, databases, etc.) in simple
human-readable configuration files — and then create, update, or destroy that infrastructure
with a single command.

**Before Terraform existed**, teams had these problems:
- Clicking through the AWS Console manually — no record of what was created
- Different environments (dev/prod) drifted apart because humans made different choices
- Onboarding a new engineer meant a 2-day handover of "tribal knowledge"
- One typo in a script could destroy a production database
- No version control for infrastructure — you couldn't roll back

**Terraform solves all of this:**

| Problem (Before)                        | Solution (Terraform)                         |
|-----------------------------------------|----------------------------------------------|
| Manual console clicking, no audit trail | Code in Git — full history of every change   |
| Dev ≠ Prod configuration                | Same code, different variable files          |
| "It works on my environment"            | Reproducible infrastructure every time       |
| Scary to change anything in prod        | `terraform plan` shows exact diff before apply |
| Vendor lock-in to one cloud             | Same tool works on AWS, Azure, GCP           |

### 🕐 Brief History

| Year | Event |
|------|-------|
| 2014 | HashiCorp releases Terraform 0.1 |
| 2017 | Terraform 0.10 — providers split into separate plugins |
| 2020 | Terraform 0.13 — `for_each` on modules |
| 2021 | Terraform 1.0 released — stable API guarantee |
| 2023 | HashiCorp changes license to BSL; **OpenTofu** fork created (MIT licensed) |

### ⚙️ How It Works — The Core Loop

```
Write .tf files  →  terraform plan  →  terraform apply  →  Infrastructure exists
      ↑                                                              |
      └──────────────── terraform destroy ←────────────────────────┘
```

Terraform maintains a **state file** (`.tfstate`) that maps your code to real AWS resources.
Every apply reads the current state, compares it to your code, and makes only the changes needed.

---

## 2. Terraform Providers

### 📖 Theory

A **provider** is a plugin that teaches Terraform how to talk to a specific API.
Without a provider, Terraform is just a language with no cloud knowledge.

Think of it like this:
- Terraform = the engine
- Provider = the steering wheel for a specific car (AWS, Azure, GCP, GitHub, etc.)

There are **3000+ providers** on the Terraform Registry.

### 💻 Practical Example

```hcl
# providers.tf

terraform {
  required_version = ">= 1.6.0"   # minimum Terraform version

  required_providers {
    aws = {
      source  = "hashicorp/aws"    # registry.terraform.io/hashicorp/aws
      version = "~> 5.0"           # any 5.x version (tilde = minor updates ok)
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # default_tags applies tags to EVERY resource automatically
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = "dev"
    }
  }
}
```

**Version Constraints Explained:**

| Constraint | Meaning |
|------------|---------|
| `= 5.0.0`  | Exactly this version |
| `>= 5.0`   | Any version 5.0 or higher |
| `~> 5.0`   | 5.x only (no 6.0) — most common |
| `>= 4.0, < 6.0` | Range |

---

## 3. terraform init — Deep Dive

### 📖 What Happens When You Run `terraform init`?

Running `terraform init` is **always the first command** in any Terraform project.
Here is exactly what happens behind the scenes — step by step:

```
$ terraform init
```

**Step 1 — Reads your .tf files**
Terraform scans the current directory for all `*.tf` files and reads `required_providers`.

**Step 2 — Downloads Providers**
It downloads provider plugins (e.g. `hashicorp/aws`) from the Terraform Registry
into the `.terraform/providers/` folder.

**Step 3 — Creates a lock file**
`.terraform.lock.hcl` is created/updated. This pins the exact provider version so
every team member uses the same binary. **Commit this file to Git.**

**Step 4 — Configures the Backend**
If you have a remote backend (S3, etc.), Terraform connects to it and verifies access.

**Step 5 — Downloads Modules**
Any `module` blocks with remote sources are downloaded into `.terraform/modules/`.

```
.terraform/
├── providers/
│   └── registry.terraform.io/hashicorp/aws/5.x.x/...   ← provider binary
├── modules/
│   └── networking/                                       ← local module (symlinked)
└── terraform.lock.hcl                                    ← pinned versions
```

### 🔁 When to Re-run `terraform init`

| Situation | Need to re-run init? |
|-----------|----------------------|
| Added a new provider | ✅ Yes |
| Changed provider version | ✅ Yes |
| Added a new module source | ✅ Yes |
| Changed a variable value | ❌ No |
| Modified resource config | ❌ No |

```bash
terraform init                    # normal
terraform init -upgrade           # upgrade providers to latest allowed version
terraform init -backend-config="bucket=my-state-bucket"  # pass backend config
terraform init -reconfigure       # force re-init the backend
```

---

## 4. Core Commands

### `terraform fmt`
Auto-formats your `.tf` files to the official style.
Run this before every commit — keeps code consistent across the team.

```bash
terraform fmt          # format current directory
terraform fmt -recursive   # format all subdirectories too
terraform fmt -check   # CI: exits non-zero if files need formatting (don't write)
```

### `terraform validate`
Checks your configuration for syntax errors and internal consistency.
Does NOT connect to AWS — runs offline.

```bash
terraform validate
# Success! The configuration is valid.
```

### `terraform plan`
The most important command. Shows you **exactly what Terraform will do** before touching anything.
Always run plan before apply.

```bash
terraform plan                          # preview changes
terraform plan -var-file="dev.tfvars"   # use a specific variable file
terraform plan -out=tfplan              # save plan to file (use in CI/CD)
```

**Reading a plan:**
```
+ create    # new resource will be created
~ update    # existing resource will be modified in-place
- destroy   # resource will be deleted
-/+ replace # resource must be destroyed and recreated (destructive!)
```

### `terraform apply`
Executes the plan and makes real changes in AWS.

```bash
terraform apply                            # interactive — asks "yes/no"
terraform apply -var-file="dev.tfvars"     # with variable file
terraform apply -auto-approve              # skip the yes/no prompt (use in CI/CD)
terraform apply -target=module.networking  # apply only one module (use carefully)
terraform apply tfplan                     # apply a saved plan file
```

### `terraform destroy`
Deletes ALL resources managed by Terraform in the current state.

```bash
terraform destroy                            # interactive confirm
terraform destroy -auto-approve              # no prompt (dangerous in prod!)
terraform destroy -target=module.cloudwatch  # destroy only one module
terraform destroy -var-file="dev.tfvars"
```

> ⚠️ **Rule:** Never run `destroy -auto-approve` in production. Always review the plan first.

---

## 5. Variables — All Types

Variables make your Terraform code reusable across environments.
Instead of hardcoding "t3.medium" everywhere, you define it once as a variable
and override it per environment.

### String

```hcl
# variables.tf
variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.medium"
}

# main.tf — usage
resource "aws_instance" "server" {
  instance_type = var.instance_type   # "t3.medium"
}
```

### Number

```hcl
variable "instance_count" {
  description = "How many EC2 instances to create"
  type        = number
  default     = 1
}

# main.tf — usage
resource "aws_instance" "server" {
  count = var.instance_count   # creates N instances
  # ...
}
```

### Boolean

```hcl
variable "enable_deletion_protection" {
  description = "Prevent RDS from being deleted"
  type        = bool
  default     = false   # false in dev, true in prod
}

resource "aws_db_instance" "main" {
  deletion_protection = var.enable_deletion_protection
}
```

### List

```hcl
variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Access by index
resource "aws_subnet" "first_public" {
  cidr_block = var.public_subnet_cidrs[0]   # "10.0.1.0/24"
}
```

### Map

```hcl
variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "learning"
    ManagedBy = "Terraform"
  }
}

resource "aws_instance" "server" {
  tags = var.common_tags
}
```

### Object (Complex Type)

```hcl
variable "ec2_config" {
  type = object({
    instance_type = string
    volume_size   = number
    encrypted     = bool
  })
  default = {
    instance_type = "t3.medium"
    volume_size   = 30
    encrypted     = true
  }
}

resource "aws_instance" "server" {
  instance_type = var.ec2_config.instance_type
}
```

### How to Pass Variable Values

**Priority order (highest wins):**

```
1. -var flag on command line
2. -var-file flag
3. terraform.tfvars (auto-loaded)
4. *.auto.tfvars (auto-loaded)
5. TF_VAR_xxx environment variable
6. default value in variable block
```

```bash
# Method 1 — var-file (recommended)
terraform apply -var-file="dev.tfvars"

# Method 2 — inline flag
terraform apply -var="instance_type=t3.large"

# Method 3 — environment variable (best for secrets)
export TF_VAR_db_password="MySecret123!"
terraform apply
```

### `sensitive` Variables

```hcl
variable "db_password" {
  type      = string
  sensitive = true   # Terraform NEVER prints this value in plan/apply output
}
```

---

## 6. Outputs

### 📖 Why Use Outputs?

Outputs expose values from your Terraform code after `apply` completes.
They serve two purposes:
1. **Print useful info** — show the EC2 public IP so you know where to SSH
2. **Pass data between modules** — module A's output becomes module B's input

```hcl
# modules/networking/outputs.tf
output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}
```

```hcl
# environments/dev/main.tf — consuming the output
module "security" {
  source = "../../modules/security"
  vpc_id = module.networking.vpc_id   # ← output from networking module
}
```

### `output depends_on`

```hcl
output "public_ips" {
  value = aws_eip.app[*].public_ip

  # CONCEPT: output depends_on
  # The EIPs must be fully associated before this output is valid.
  # Without this, the output could return null during apply.
  depends_on = [aws_eip.app]
}
```

### Sensitive Output

```hcl
output "rds_password" {
  value     = random_password.rds.result
  sensitive = true   # shown as <sensitive> in terminal, not plain text
}
```

---

## 7. Lifecycle Policy

### 📖 Theory

The `lifecycle` block controls how Terraform **creates, updates, and destroys** a resource.
By default, Terraform destroys-then-creates when a resource must be replaced.
Lifecycle lets you change that behavior.

### `create_before_destroy`

**Problem it solves:** When replacing a security group attached to an EC2 instance,
Terraform tries to delete the old SG first — but EC2 still references it → ERROR.

```hcl
resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = var.vpc_id

  lifecycle {
    create_before_destroy = true
    # Terraform creates the NEW security group first,
    # updates EC2 to use it, THEN deletes the old one.
    # Zero downtime replacement.
  }
}
```

### `prevent_destroy`

**Problem it solves:** Someone accidentally runs `terraform destroy` on the production database.

```hcl
resource "aws_db_instance" "prod" {
  identifier = "prod-mysql"

  lifecycle {
    prevent_destroy = true
    # terraform destroy will FAIL with an error — database is protected.
    # Must manually remove this flag before you can delete the resource.
  }
}
```

### `ignore_changes`

**Problem it solves:** Auto-scaling changes the desired count, Terraform tries to revert it on next apply.

```hcl
resource "aws_eks_node_group" "main" {
  scaling_config {
    desired_size = 2
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      # Terraform will not try to reset the count that auto-scaling changed.
    ]
  }
}
```

Another common use — ignore AMI updates so existing EC2 isn't replaced:

```hcl
resource "aws_instance" "server" {
  ami = data.aws_ami.ubuntu.id

  lifecycle {
    ignore_changes = [ami]
    # If a new Ubuntu AMI is released, don't replace the running instance.
    # Only a new instance will use the new AMI.
  }
}
```

### Summary Table

| Policy | Use When |
|--------|----------|
| `create_before_destroy = true` | Replacing a resource that other resources depend on |
| `prevent_destroy = true` | Production databases, critical S3 buckets |
| `ignore_changes = [field]` | Auto-scaling, manually rotated passwords, AWS-managed fields |

---

## 8. Locals

### 📖 Theory

Locals are **computed values you define once and reuse** throughout a module.
They reduce repetition and keep logic in one place.

Think of locals like constants in programming.

```hcl
# Without locals — repeated everywhere, error-prone:
resource "aws_instance" "server" {
  tags = {
    Environment = "dev"
    Project     = "learning"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "app" {
  tags = {
    Environment = "dev"
    Project     = "learning"
    ManagedBy   = "Terraform"
  }
}
```

```hcl
# With locals — define once, use everywhere:
locals {
  common_tags = {
    Environment = var.environment
    Project     = "learning"
    ManagedBy   = "Terraform"
  }

  # computed value — use anywhere
  bucket_name = "${var.environment}-app-${random_id.suffix.hex}"
}

resource "aws_instance" "server" {
  tags = local.common_tags   # clean!
}

resource "aws_s3_bucket" "app" {
  bucket = local.bucket_name
  tags   = local.common_tags
}
```

---

## 9. Data Sources

### 📖 Theory

A **data source** reads information from AWS (or another provider) without creating anything.
Use it when you need to reference existing resources that Terraform doesn't manage.

**Common uses:**
- Get the latest Ubuntu AMI ID (changes every few weeks)
- Look up an existing VPC by name
- Get the current AWS account ID
- Read a secret from Secrets Manager

```hcl
# EXAMPLE 1: Latest Ubuntu 22.04 AMI — never hardcode an AMI ID!
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "server" {
  ami = data.aws_ami.ubuntu.id   # always uses latest — no manual updates needed
}
```

```hcl
# EXAMPLE 2: Current AWS account ID
data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "alerts" {
  policy = jsonencode({
    Statement = [{
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}
```

```hcl
# EXAMPLE 3: Available AZs in the region — no hardcoding "us-east-1a"
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  availability_zone = data.aws_availability_zones.available.names[0]
}
```

---

## 10. count vs for_each

### 📖 Theory

Both `count` and `for_each` create multiple instances of a resource.
They solve different problems. Choosing the wrong one causes headaches.

### `count` — Use for identical numbered resources

```hcl
# Create 3 EC2 instances — they are identified by INDEX (0, 1, 2)
resource "aws_instance" "server" {
  count         = 3
  instance_type = "t3.medium"
  ami           = data.aws_ami.ubuntu.id

  tags = {
    Name = "server-${count.index}"   # server-0, server-1, server-2
  }
}

# Access specific instance:
output "first_server_id" {
  value = aws_instance.server[0].id
}

# Access all:
output "all_server_ids" {
  value = aws_instance.server[*].id   # [id0, id1, id2]
}
```

**Problem with count:** If you remove item [1] from a list,
Terraform reindexes — items [2] becomes [1] → Terraform DESTROYS and RECREATES resources!

### `for_each` — Use for named/unique resources

```hcl
# Create subnets from a MAP — identified by KEY not index
resource "aws_subnet" "public" {
  for_each = {
    "public-a" = { cidr = "10.0.1.0/24", az = "us-east-1a" }
    "public-b" = { cidr = "10.0.2.0/24", az = "us-east-1b" }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr      # each.value = the object
  availability_zone = each.value.az
  
  tags = { Name = each.key }   # each.key = "public-a" or "public-b"
}

# Removing "public-b" only deletes that specific subnet.
# "public-a" is untouched. ← This is the key advantage over count.
```

```hcl
# for_each on a SET of strings (simpler)
resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = each.value   # each.value = the ARN string
}
```

### Decision Guide

| Use `count` when... | Use `for_each` when... |
|---------------------|------------------------|
| Resources are truly identical | Resources have unique names/configs |
| Simple toggle (0 or 1) | Working with a map or set |
| Order doesn't matter | Removing one item shouldn't affect others |
| RDS read replicas | Subnets, security group rules, IAM policies |

---

## 11. Terraform Drift

### 📖 Theory

**Drift** = your real AWS infrastructure no longer matches your Terraform state/code.

**How drift happens:**
- Someone manually changes a security group in the AWS Console
- AWS automatically updates a field (e.g., EKS adds its own security group)
- A team member uses the CLI directly: `aws ec2 modify-instance-attribute ...`

### Detecting Drift

```bash
# terraform plan always shows drift
terraform plan

# If someone manually added a rule to a security group:
# ~ aws_security_group.web will be updated in-place
#   ~ ingress = [   (rule manually added in console will be removed!)
```

### Fixing Drift

```bash
# Option 1: Let Terraform fix it — run apply to restore desired state
terraform apply

# Option 2: Accept the manual change — import it into state
terraform import aws_security_group_rule.manual sgr-0abc123456

# Option 3: Add ignore_changes so Terraform stops fighting it
lifecycle {
  ignore_changes = [ingress]
}
```

### Preventing Drift — Best Practices

1. **Lock down Console access** — only Terraform should touch managed resources
2. **Run `terraform plan` in CI on a schedule** — detect drift automatically
3. **Use `ignore_changes`** for fields AWS manages automatically

---

## 12. Backends — Local vs Remote

### 📖 Theory

Terraform stores the **state file** (`terraform.tfstate`) in a **backend**.
The state file is the single source of truth about what resources Terraform created.

**Local Backend** (default — no config needed):
- State file stored on your laptop: `./terraform.tfstate`
- Problem: If your laptop dies, state is gone. Team can't share it.

**Remote Backend** (S3 + DynamoDB — production standard):
- State stored in S3 — safe, versioned, shared
- DynamoDB provides locking — prevents two people applying at once

### Local Backend Example

```hcl
# Nothing needed — this is the default behavior.
# State file: ./terraform.tfstate
```

### Remote Backend (S3) Example

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-123456789"   # your S3 bucket
    key            = "dev/terraform.tfstate"           # path inside the bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-dev"              # DynamoDB for locking
    encrypt        = true                              # encrypt state at rest
  }
}
```

Each environment uses a **different key** (path) so states are fully isolated:
- dev  → `dev/terraform.tfstate`
- test → `test/terraform.tfstate`
- prod → `prod/terraform.tfstate`

### Setup (one-time)

```bash
# 1. Create S3 bucket
aws s3api create-bucket --bucket my-terraform-state-123456789 --region us-east-1

# 2. Enable versioning (recover accidentally deleted state)
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-123456789 \
  --versioning-configuration Status=Enabled

# 3. Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-lock-dev \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

---

## 13. State Locking — Why It Matters

### 📖 Theory

When Terraform runs `apply`, it places a **lock** on the state file.
This prevents another `apply` from running at the same time and corrupting the state.

### What Happens WITHOUT a Lock

```
Engineer A:  terraform apply   ← reads state, plans to create RDS
Engineer B:  terraform apply   ← also reads state (same snapshot)

Engineer A:  Creates RDS instance (id: rds-001)   ← writes to state
Engineer B:  Creates RDS instance (id: rds-002)   ← OVERWRITES state

Result: Two RDS instances exist in AWS, but state only knows about one.
        Terraform can never manage rds-002 again. Manual cleanup needed.
        Possible data loss. Production incident.
```

### What Happens WITH DynamoDB Lock

```
Engineer A:  terraform apply
  → Acquires lock:  LockID = "dev/terraform.tfstate"
  → Starts applying...

Engineer B:  terraform apply  (runs at the same time)
  → Tries to acquire lock
  → BLOCKED: "Error: state file is locked by another process"
  → Engineer B waits until Engineer A finishes

Engineer A:  Apply complete → releases lock
Engineer B:  Acquires lock → runs safely
```

### Lock Info

```bash
# If a lock gets stuck (Engineer A's laptop crashed mid-apply):
terraform force-unlock LOCK_ID

# See current lock info:
terraform plan   # will show lock error with the LockID if locked
```

---

## 14. Workspaces

### 📖 Theory

Workspaces let you maintain **multiple state files** within the same Terraform configuration.
Each workspace is isolated — `dev` workspace state doesn't affect `prod` workspace state.

> **Note:** For serious multi-environment setups, separate directories (like this repo uses)
> is more common in production. Workspaces are better for short-lived feature branches.

### Commands

```bash
# List all workspaces
terraform workspace list
# * default         ← currently selected

# Create a new workspace
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Switch workspace
terraform workspace select prod

# Show current workspace
terraform workspace show
# prod

# Delete a workspace (must be empty — no resources)
terraform workspace delete staging
```

### Using Workspace in Code

```hcl
locals {
  # Change instance size automatically based on workspace
  instance_type = {
    dev     = "t3.micro"
    staging = "t3.medium"
    prod    = "t3.large"
  }
}

resource "aws_instance" "server" {
  instance_type = local.instance_type[terraform.workspace]
}
```

---

## 15. Modules

### 📖 Theory

A **module** is a reusable package of Terraform resources grouped together.
It is just a folder with `.tf` files inside.

**Problem without modules:**
```
# 1000 lines of EC2 + VPC + RDS + EKS all in one main.tf
# Can't reuse for dev vs prod
# One change breaks everything
# Impossible to test in isolation
```

**Problem WITH modules:**
```
modules/networking/   ← reusable VPC code
modules/compute/      ← reusable EC2 code
modules/rds/          ← reusable database code

environments/dev/     ← calls modules with dev-sized values
environments/prod/    ← calls same modules with prod-sized values
```

### Module Structure (this repo)

```hcl
# Module definition: modules/networking/main.tf
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

# Module definition: modules/networking/variables.tf
variable "vpc_cidr" { type = string }

# Module definition: modules/networking/outputs.tf
output "vpc_id" { value = aws_vpc.main.id }
```

```hcl
# Module consumption: environments/dev/main.tf
module "networking" {
  source = "../../modules/networking"   # path to the module

  vpc_cidr = "10.0.0.0/16"   # input variable
}

# Use the module's output in another module
module "security" {
  source = "../../modules/security"
  vpc_id = module.networking.vpc_id   # ← output from networking module
}
```

### Module Sources

```hcl
# Local path (this repo)
source = "../../modules/networking"

# Terraform Registry (public module)
source  = "terraform-aws-modules/vpc/aws"
version = "5.1.0"

# Git
source = "git::https://github.com/org/repo.git//modules/vpc?ref=v1.0.0"

# S3
source = "s3::https://s3.amazonaws.com/mybucket/modules/vpc.zip"
```

### Why Use Modules?

| Without Modules | With Modules |
|-----------------|--------------|
| Copy-paste code across envs | Write once, call with different vars |
| Change affects everything | Change isolated to one module |
| No clear ownership | Each module owned by one team |
| Hard to test | Test each module independently |

---

## 16. All Terraform Commands — Real World Reference

```bash
# ─────────────────────────────────────────────
# SETUP & INITIALIZATION
# ─────────────────────────────────────────────

terraform init                    # Initialize: download providers + modules
terraform init -upgrade           # Upgrade providers to latest allowed version
terraform init -reconfigure       # Force re-configure the backend
terraform init -backend-config="bucket=my-bucket"  # Pass backend config at runtime


# ─────────────────────────────────────────────
# CODE QUALITY
# ─────────────────────────────────────────────

terraform fmt                     # Auto-format code (run before every commit)
terraform fmt -recursive          # Format all subdirectories
terraform fmt -check              # CI check: fail if code not formatted

terraform validate                # Check syntax (offline, no AWS call)


# ─────────────────────────────────────────────
# PLAN & APPLY
# ─────────────────────────────────────────────

terraform plan                              # Preview changes
terraform plan -var-file="dev.tfvars"       # With variable file
terraform plan -out=tfplan                  # Save plan to file for apply later
terraform plan -target=module.networking    # Plan only one module

terraform apply                             # Apply changes (interactive)
terraform apply -auto-approve               # Apply without yes/no prompt (CI/CD)
terraform apply -var-file="prod.tfvars"     # With variable file
terraform apply tfplan                      # Apply from saved plan file
terraform apply -target=module.compute      # Apply only one resource/module
terraform apply -replace=aws_instance.web   # Force replace a specific resource


# ─────────────────────────────────────────────
# DESTROY
# ─────────────────────────────────────────────

terraform destroy                               # Destroy all resources (interactive)
terraform destroy -auto-approve                 # No prompt — dangerous in prod!
terraform destroy -target=module.cloudwatch     # Destroy only one module
terraform destroy -var-file="dev.tfvars"


# ─────────────────────────────────────────────
# STATE MANAGEMENT
# ─────────────────────────────────────────────

terraform state list                          # List all resources in state
terraform state show aws_instance.server      # Show details of one resource
terraform state mv aws_instance.old aws_instance.new  # Rename resource in state
terraform state rm aws_instance.server        # Remove from state (doesn't delete AWS resource)
terraform state pull                          # Download remote state to stdout
terraform state push terraform.tfstate        # Upload local state to remote backend

terraform import aws_instance.server i-0abc123  # Import existing AWS resource into state


# ─────────────────────────────────────────────
# OUTPUTS & INSPECTION
# ─────────────────────────────────────────────

terraform output                        # Print all outputs
terraform output vpc_id                 # Print one specific output
terraform output -json                  # JSON format (useful in scripts)
terraform output -raw eks_cluster_name  # Raw value without quotes


# ─────────────────────────────────────────────
# GRAPH & DEBUG
# ─────────────────────────────────────────────

terraform graph                         # Print dependency graph (DOT format)
terraform graph | dot -Tpng > graph.png # Visualize graph (requires Graphviz)

terraform show                          # Show current state in human-readable form
terraform show tfplan                   # Show saved plan file

terraform version                       # Terraform + provider versions
terraform providers                     # List all providers in config


# ─────────────────────────────────────────────
# WORKSPACES
# ─────────────────────────────────────────────

terraform workspace list
terraform workspace new dev
terraform workspace select prod
terraform workspace show
terraform workspace delete staging


# ─────────────────────────────────────────────
# LOCKING
# ─────────────────────────────────────────────

terraform force-unlock LOCK_ID          # Release a stuck state lock (use carefully)


# ─────────────────────────────────────────────
# MISCELLANEOUS
# ─────────────────────────────────────────────

terraform taint aws_instance.server     # (deprecated → use -replace) Mark for recreation
terraform refresh                       # Sync state with real AWS (deprecated, plan does this)
terraform console                       # Interactive console to test expressions
```

---

## 17. This Repo — Module Map

```
AWS-Terraform-Modules/
│
├── modules/
│   ├── networking/       VPC · 2 public + 2 private subnets · IGW · NAT · route tables
│   ├── security/         EC2 SG (22/443/8080) · RDS SG · EKS cluster + node SGs
│   ├── compute/          Ubuntu EC2 · key pair "devops" · EIP · user_data install script
│   ├── storage/          S3 · versioning · AES-256 · lifecycle rules
│   ├── iam/              EC2 role (SSM+S3+Secrets) · EKS cluster role · EKS node role
│   ├── eks/              EKS cluster · managed node group · 4 add-ons
│   ├── rds/              MySQL primary · read replicas (count) · parameter group
│   ├── sns/              SNS topic · topic policy · email subscriptions (for_each)
│   ├── secrets_manager/  Auto-generated password · stored as JSON · read IAM policy
│   └── cloudwatch/       3 dashboards · 10 alarms (for_each) · SNS wired
│
└── environments/
    ├── dev/    Small (t3.medium, db.t3.micro,  1 replica,  no multi-AZ)
    ├── test/   Medium (t3.medium, db.t3.small, 2 replicas, no multi-AZ)
    └── prod/   Large  (t3.large,  db.t3.medium, 2 replicas, Multi-AZ, deletion_protection=true)
```

**Apply Order (enforced by `depends_on`):**
```
storage → sns → secrets_manager → networking → security
→ iam → compute → eks → rds → cloudwatch
```

**Destroy Order (exact reverse — automatic):**
```
cloudwatch → rds → eks → compute → iam → security
→ networking → secrets_manager → sns → storage
```

**Terraform Concepts Used in This Repo:**

| Concept | Location |
|---------|----------|
| `count` | compute (instances, EIPs), rds (replicas) |
| `for_each` | networking (subnets), security (dynamic rules), iam (policy sets), sns (subscriptions), cloudwatch (all 10 alarms) |
| `dynamic` block | security (ingress rules) |
| `depends_on` | All environment main.tf files |
| `output depends_on` | compute/outputs.tf |
| `lifecycle create_before_destroy` | security, storage, rds param group |
| `lifecycle ignore_changes` | compute (ami), eks (desired_size), rds (password) |
| `lifecycle prevent_destroy` | storage (prod S3 bucket) |
| `locals` | networking, cloudwatch, iam, all environments |
| `data` source | compute (AMI lookup), iam (policy docs), sns (account ID) |
| `sensitive` variable/output | rds (password), eks (cluster cert), secrets_manager |
| Remote S3 backend | All 3 environments (separate state file per env) |
| `jsonencode()` | cloudwatch dashboards, sns policy |
| `toset()` | iam (policy ARN sets) |
| `merge()` | Every resource's tags |
| `random_password` | secrets_manager module |

---

## 18. Interview Questions

> Basic to Intermediate — 3-line answers, real-world focused.

---

**Q1. What happens when you run `terraform init`?**

Terraform reads `required_providers` and downloads provider plugins into `.terraform/providers/`.
It creates `.terraform.lock.hcl` to pin exact versions for team consistency.
If a remote backend is configured, it also initializes the backend connection.

---

**Q2. What is a lifecycle policy in Terraform? Name the 3 main options.**

Lifecycle controls how Terraform creates, updates, and destroys a resource.
`create_before_destroy` creates the replacement before deleting the old one (zero downtime).
`prevent_destroy` blocks deletion (protects prod databases). `ignore_changes` tells Terraform
to stop tracking specific fields (e.g., auto-scaling changes to desired_size).

---

**Q3. Two engineers run `terraform apply` at the same time. What happens?**

If using a remote backend with DynamoDB locking, the second engineer gets a lock error
and is blocked until the first apply completes — state is safe.
Without locking (local backend), both read the same state, both write, and one overwrites
the other — causing orphaned resources, drift, and potential production incidents.

---

**Q4. What is the difference between `count` and `for_each`?**

`count` creates resources by index (0, 1, 2) — removing one item re-indexes and
triggers destroy/recreate of all following resources.
`for_each` uses a map/set with named keys — removing one entry only deletes that
specific resource, leaving others untouched. Use `for_each` for uniquely named resources.

---

**Q5. What is Terraform state and why is it important?**

The state file (`.tfstate`) is Terraform's memory — it maps your HCL resources to real
AWS resource IDs. Without it, Terraform doesn't know what it created and would try
to create everything again. It also stores attribute values (IPs, ARNs) used by other resources.

---

**Q6. What is terraform drift and how do you detect/fix it?**

Drift is when the real infrastructure differs from the Terraform state/code — usually
caused by manual Console or CLI changes. Running `terraform plan` always detects drift
because it compares real AWS state to desired state. Fix it by running `apply` to restore
desired state, or `import` + `ignore_changes` to accept the manual change.

---

**Q7. What is the difference between a local and remote backend?**

Local backend stores state on disk (`./terraform.tfstate`) — fine for solo learning
but risky for teams (lost if laptop dies, no locking, can't share).
Remote backend (S3 + DynamoDB) stores state centrally with versioning, encryption,
and locking — required for any team or production use.

---

**Q8. What is a data source? How is it different from a resource?**

A `resource` creates something new in AWS. A `data` source only reads existing information.
For example, `data "aws_ami" "ubuntu"` looks up the latest Ubuntu AMI ID without creating
anything. Use data sources to reference things Terraform doesn't manage (existing VPCs, AMIs, account IDs).

---

**Q9. What is `sensitive = true` on a variable or output?**

It marks the value as secret — Terraform redacts it from all plan/apply terminal output
and marks it as `(sensitive)` in state. It prevents passwords, tokens, and keys from
appearing in CI/CD logs. Note: the value is still stored in state, so encrypt your backend.

---

**Q10. What is a Terraform module and why use it?**

A module is a reusable folder of `.tf` files that accepts inputs (variables) and
returns outputs. It solves copy-paste duplication — write networking code once,
call it from dev/test/prod with different variable values. Modules enforce consistency,
enable testing in isolation, and give clear ownership to teams.

---

## 🚀 Quick Start

```bash
# 1. Go to an environment
cd environments/dev

# 2. Initialize (download providers)
terraform init \
  -backend-config="bucket=YOUR_STATE_BUCKET" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-lock-dev" \
  -backend-config="encrypt=true"

# 3. Format and validate
terraform fmt -recursive
terraform validate

# 4. Preview
terraform plan -var-file="dev.tfvars"

# 5. Apply
terraform apply -var-file="dev.tfvars"

# 6. See outputs
terraform output

# 7. Clean up (dev only — never auto-approve prod!)
terraform destroy -var-file="dev.tfvars"
```

---

*Built for students. Every concept is intentional. Every comment explains why.*
*Start from module 1 and work down — each section builds on the previous.*
