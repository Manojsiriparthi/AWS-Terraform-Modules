# 🖥️ Module: Compute (EC2 Instance)

> **Spoon-feeding guide — every single line explained.**
> Read top to bottom. Each section builds on the previous one.

---

## 📦 What Does This Module Create?

| Resource | What it is |
|----------|-----------|
| `aws_ami` (data source) | Looks up the latest Ubuntu 22.04 image ID automatically |
| `aws_key_pair` | SSH key pair registered in AWS so you can log into the server |
| `aws_instance` | The actual EC2 virtual machine (your server) |
| `aws_eip` | A static public IP address permanently attached to the instance |

---

## 📁 Files in This Module

```
modules/compute/
├── main.tf          ← all resources defined here
├── variables.tf     ← all inputs this module accepts
├── outputs.tf       ← values exposed after apply
├── README.md        ← this file
└── scripts/
    └── install.sh   ← runs on first boot: installs Jenkins, Docker, Terraform
```

---

## 🔍 PART 1 — Data Source: `aws_ami`

### What is a Data Source?

A **data source** does NOT create anything.
It only **reads** existing information from AWS and gives it to you.

Think of it like a Google search — you ask a question, AWS answers.

```
"What is the latest Ubuntu 22.04 AMI ID in us-east-1?"
AWS answers: "ami-0c7217cdde317cfec"
```

You then use that answer in your `aws_instance` resource.

---

### With vs Without a Data Source

**❌ WITHOUT a data source (hardcoded AMI — bad):**

```hcl
resource "aws_instance" "server" {
  ami = "ami-0c7217cdde317cfec"   # ← THIS WILL BREAK
  # Problems:
  # 1. AMI IDs are REGION-SPECIFIC. This ID only works in us-east-1.
  #    Deploy to us-west-2? Terraform throws an error.
  # 2. AMI IDs EXPIRE. Ubuntu releases new AMIs every few weeks.
  #    Old ones get deregistered. Your apply breaks silently months later.
  # 3. Security patches — the old AMI may have unpatched vulnerabilities.
  #    You'd never know because you never updated the ID.
}
```

**✅ WITH a data source (dynamic lookup — correct):**

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true   # always grab the newest matching AMI
  owners      = ["099720109477"]   # only trust Canonical's official images

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "server" {
  ami = data.aws_ami.ubuntu.id   # ← always correct, always latest, any region
}
```

---

### Line-by-Line: `data "aws_ami" "ubuntu"`

```hcl
data "aws_ami" "ubuntu" {
```
- `data` → keyword that means "read something, don't create"
- `"aws_ami"` → what to read (an Amazon Machine Image)
- `"ubuntu"` → local name you give it, used as `data.aws_ami.ubuntu.id` later

```hcl
  most_recent = true
```
- When multiple AMIs match the filters, pick the **newest one**.
- Ubuntu publishes updated AMIs regularly. `most_recent = true` ensures you always
  get the latest patched version automatically — no manual ID updates needed.

```hcl
  owners = ["099720109477"]
```
- **This is Canonical's official AWS account ID** (Ubuntu's publisher).
- Why does this matter? Anyone can publish an AMI named "ubuntu-22.04".
  A malicious publisher could upload an infected image with the same name.
- Filtering by `owners` means **only Canonical's official images** can match.
- Without this: you could accidentally boot a server from an untrusted, possibly
  backdoored image.

```hcl
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
```
- `filter` narrows down the results. Like a WHERE clause in SQL.
- `name = "name"` → we are filtering by the AMI's **name field**.
- `values = [...]` → the pattern to match. The `*` is a wildcard.
- Breaking down the pattern:
  - `ubuntu/images/` → official Canonical path
  - `hvm-ssd/` → HVM virtualization type, SSD storage (fastest)
  - `ubuntu-jammy-22.04` → Ubuntu 22.04 LTS codename "Jammy Jellyfish"
  - `amd64-server-*` → 64-bit server, any date suffix

```hcl
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
```
- A second filter to ensure only `hvm` (Hardware Virtual Machine) type.
- HVM is the modern standard — better performance than the old `paravirtual` type.
- All current instance types (t3, m5, c5, etc.) require HVM.

---

## 🔑 PART 2 — Resource: `aws_key_pair`

### What is an SSH Key Pair?

To log into a Linux server, you need SSH authentication.
AWS uses **asymmetric key cryptography**:

```
You have:                         AWS stores:
┌─────────────────────┐           ┌─────────────────────┐
│  Private Key        │           │  Public Key         │
│  ~/.ssh/id_rsa      │           │  aws_key_pair       │
│  (NEVER share this) │           │  (safe to share)    │
└─────────────────────┘           └─────────────────────┘
        │                                   │
        └──── SSH handshake ────────────────┘
              "prove you have the private key"
```

- Your **private key** stays on YOUR laptop. AWS never sees it.
- Your **public key** is uploaded to AWS and put in the EC2 instance's
  `~/.ssh/authorized_keys` file on boot.
- When you SSH in, your laptop proves it holds the private key → access granted.

---

### How to Generate an SSH Key (one-time setup)

```bash
# Generate a key pair on your laptop
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# This creates two files:
# ~/.ssh/id_rsa       ← PRIVATE KEY — never share, never commit to Git
# ~/.ssh/id_rsa.pub   ← PUBLIC KEY  — safe to upload to AWS
```

---

### With vs Without a Key Pair

**❌ WITHOUT a key pair:**
```
EC2 instance starts. You have no way to SSH in.
You're locked out of your own server.
You cannot debug, deploy code, or check logs.
```

**✅ WITH a key pair:**
```bash
ssh -i ~/.ssh/id_rsa ubuntu@<EC2-PUBLIC-IP>
# You're in! ubuntu@ip-10-0-1-42:~$
```

---

### Line-by-Line: `resource "aws_key_pair" "devops"`

```hcl
resource "aws_key_pair" "devops" {
```
- `resource` → create something in AWS
- `"aws_key_pair"` → the AWS resource type (key pair)
- `"devops"` → local name for this resource in Terraform

```hcl
  key_name = var.key_name
```
- The name that appears in the AWS Console under EC2 → Key Pairs.
- Value comes from the variable `key_name`, default is `"devops"`.
- This is the name you reference when launching an instance.

```hcl
  public_key = file(var.public_key_path)
```
- `file(...)` is a built-in Terraform function that reads a file from disk
  and returns its contents as a string.
- `var.public_key_path` is the path to your public key, default `~/.ssh/id_rsa.pub`.
- So this reads your public key file and uploads its content to AWS.
- Example of what the public key file looks like:
  ```
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-email@example.com
  ```

```hcl
  tags = merge(var.common_tags, {
    Name = "${var.environment}-devops-key"
  })
```
- `merge()` combines two maps into one.
- `var.common_tags` → tags like `Environment=dev`, `ManagedBy=Terraform`
- The second map adds a `Name` tag specific to this resource.
- Result: `{ Environment="dev", ManagedBy="Terraform", Name="dev-devops-key" }`
- Tags help you find resources in the AWS Console and track costs per environment.

---

## 💻 PART 3 — Resource: `aws_instance`

### What is an EC2 Instance?

EC2 (Elastic Compute Cloud) is AWS's virtual machine service.
You are renting a computer in AWS's data centre that runs 24/7 until you stop it.

A `t3.medium` instance for example gives you:
- 2 virtual CPUs
- 4 GB RAM
- Network connectivity
- Ubuntu OS (from the AMI we selected above)

---

### What is `count`?

```hcl
count = var.instance_count   # default 1
```

`count` is a Terraform meta-argument that creates **N copies** of a resource.

```
count = 1  →  aws_instance.app_server[0]   (1 instance)
count = 3  →  aws_instance.app_server[0]
               aws_instance.app_server[1]
               aws_instance.app_server[2]
```

In dev we create 1 instance. In prod we create 2 for redundancy.
The same code works for both — just change the `instance_count` variable.

---

### What is `user_data`?

`user_data` is a script that AWS runs **once**, automatically, when the instance
first boots up. It runs as root. You can use it to install software.

```
Instance starts
    ↓
AWS injects your script
    ↓
Script runs (installs Jenkins, Docker, Terraform, kubectl)
    ↓
Server is ready to use
```

Without user_data, you'd have to:
1. SSH into every new server manually
2. Run installation commands by hand
3. Hope you didn't forget any step
4. Repeat for every dev/test/prod server

With user_data, it's **automated, repeatable, and documented in code**.

---

### Line-by-Line: `resource "aws_instance" "app_server"`

```hcl
resource "aws_instance" "app_server" {
```
- Create an EC2 virtual machine.
- `"app_server"` is the local Terraform name. Refer to it as
  `aws_instance.app_server[0].id` elsewhere.

```hcl
  count = var.instance_count
```
- How many instances to create. Comes from the `instance_count` variable.
- dev.tfvars sets this to `1`. prod.tfvars sets it to `2`.

```hcl
  ami = data.aws_ami.ubuntu.id
```
- Which operating system to install on the server.
- We use the data source result from PART 1 — always the latest Ubuntu 22.04.
- `data.aws_ami.ubuntu` → the data source block.
- `.id` → the attribute we want (the AMI ID string like `ami-0c7217cdde317cfec`).

```hcl
  instance_type = var.instance_type
```
- The hardware size of the virtual machine.
- `t3.medium` = 2 vCPUs, 4 GB RAM — good for Jenkins + Docker.
- `t3.micro` = 2 vCPUs, 1 GB RAM — free tier, too small for Jenkins.
- `t3.large` = 2 vCPUs, 8 GB RAM — production use.

```hcl
  key_name = aws_key_pair.devops.key_name
```
- Attach the key pair we created in PART 2 to this instance.
- AWS places the public key in the instance's `authorized_keys` on boot.
- References the key pair resource directly — Terraform knows to create
  the key pair BEFORE the instance (implicit dependency).

```hcl
  subnet_id = var.public_subnet_id
```
- Which network segment (subnet) to place the instance in.
- We place it in a **public subnet** so it gets internet access.
- Value comes from the networking module output: `module.networking.public_subnet_ids[0]`.

```hcl
  vpc_security_group_ids = [var.security_group_id]
```
- Attach a security group — the firewall rules for this instance.
- Controls what traffic is allowed in (ports 22, 443, 8080) and out (all).
- Value comes from the security module: `module.security.ec2_security_group_id`.
- It's a **list** because you can attach multiple security groups.

```hcl
  iam_instance_profile = var.iam_instance_profile
```
- Attach an IAM role to this instance.
- This allows the EC2 instance to call AWS services without storing credentials.
- With this profile, the instance can:
  - Connect via SSM Session Manager (browser-based terminal — no SSH port needed)
  - Read/write the S3 bucket
  - Read the RDS password from Secrets Manager
  - Push metrics to CloudWatch

```hcl
  user_data = file("${path.module}/scripts/install.sh")
```
- `file(...)` reads the install script and passes it as the user_data payload.
- `${path.module}` is a built-in Terraform variable that means
  "the directory where this .tf file lives" — so the path is always correct
  regardless of where you run Terraform from.
- The script installs: Docker, Jenkins, Terraform, AWS CLI, kubectl.
- Runs once on first boot. Check `/var/log/user-data.log` to see its output.

---

### `root_block_device` — The Server's Hard Drive

```hcl
  root_block_device {
```
- Configure the main disk attached to the instance.

```hcl
    volume_type = "gp3"
```
- `gp3` = General Purpose SSD version 3. The current best default.
- Faster and cheaper than `gp2` (older default).
- Other options: `io1`/`io2` (ultra-fast SSD for databases), `st1` (HDD for bulk data).

```hcl
    volume_size = var.root_volume_size   # default 30 GB
```
- Disk size in gigabytes.
- 30 GB is enough for the OS + Jenkins + Docker images.
- Increase if you store large build artefacts.

```hcl
    delete_on_termination = true
```
- When the EC2 instance is terminated (deleted), also delete this disk.
- Set `false` if you want to keep the disk for forensics or data recovery.
- `true` is correct for ephemeral dev servers — no orphaned volumes wasting money.

```hcl
    encrypted = true
```
- Encrypt the disk at rest using AWS KMS.
- If someone physically removed the disk from AWS hardware, data is unreadable.
- This is a security best practice. Always set `true`.

---

### `lifecycle` Block on the Instance

```hcl
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [ami]
  }
```

**`create_before_destroy = true`:**
- Normal Terraform replace order: delete old → create new.
- Problem: during the gap, the instance is gone. Downtime.
- With this setting: create new → verify → delete old.
- Zero downtime replacement.

**`ignore_changes = [ami]`:**
- Problem without this: A new Ubuntu AMI releases. Terraform detects the AMI ID
  changed. Terraform wants to DESTROY your running server and create a new one.
  Your Jenkins jobs, Docker containers, and everything on that server is wiped.
- With this: Terraform stops tracking the `ami` field after first creation.
  A new AMI won't trigger instance replacement.
- New instances (from scaling) will use the new AMI. Existing servers are untouched.

---

### Tags on the Instance

```hcl
  tags = merge(var.common_tags, {
    Name = "${var.environment}-app-server-${count.index}"
    Role = "app-server"
  })
```

- `count.index` is the current iteration number (0, 1, 2...).
- When `instance_count = 2`, two instances are created with names:
  - `dev-app-server-0`
  - `dev-app-server-1`
- `Role = "app-server"` — useful for filtering instances in the AWS Console
  or for targeting with Systems Manager.

---

## 📌 PART 4 — Resource: `aws_eip` (Elastic IP)

### What is an Elastic IP?

When you start an EC2 instance, AWS gives it a **dynamic public IP**.
The problem: every time you stop and restart the instance, the IP changes.

```
Start instance:   public IP = 54.123.45.67
Stop instance.
Start instance:   public IP = 18.234.56.78   ← different!
```

This breaks:
- DNS records (your domain still points to the old IP)
- Firewall rules in other systems
- Jenkins webhook URLs
- Any bookmark or script that hardcodes the IP

An **Elastic IP (EIP)** is a **static** public IP that stays the same forever,
even if you stop/start the instance.

```
Start instance:   EIP = 52.10.20.30
Stop instance.
Start instance:   EIP = 52.10.20.30   ← same! always
```

---

### With vs Without an EIP

**❌ Without EIP:**
```
You set up Jenkins at http://54.123.45.67:8080
You configure GitHub webhook to call that IP.
Instance restarts overnight.
New IP: 18.234.56.78
GitHub webhook fails. Jenkins never gets notified. Builds stop.
You spend an hour wondering why CI is broken.
```

**✅ With EIP:**
```
Jenkins always at http://52.10.20.30:8080
Instance can restart any number of times.
GitHub webhook keeps working.
No surprises.
```

---

### With vs Without `depends_on` on EIP

**❌ Without `depends_on`:**
```
Terraform creates the EIP before the Internet Gateway exists.
AWS tries to route traffic for this EIP — but there's no IGW yet.
The EIP is created but immediately non-functional.
When Terraform creates the IGW next, the EIP still isn't properly associated.
Result: instance has an IP but no internet connectivity. Confusing to debug.
```

**✅ With `depends_on = [var.internet_gateway_id]`:**
```
Terraform waits for the Internet Gateway to exist first.
Then creates the EIP.
The EIP is immediately routable because the IGW is already in place.
Internet works on first apply.
```

---

### Line-by-Line: `resource "aws_eip" "app_server"`

```hcl
resource "aws_eip" "app_server" {
```
- Create an Elastic IP resource.
- `"app_server"` matches the instance name — keeps things readable.

```hcl
  count = var.instance_count
```
- Create one EIP **per instance**.
- If `instance_count = 2`, we get two EIPs: `aws_eip.app_server[0]` and `[1]`.
- Each EIP is attached to its matching instance using `count.index` below.

```hcl
  instance = aws_instance.app_server[count.index].id
```
- Attach this EIP to the instance at the **same index**.
- `count.index` is the loop counter (0, 1, 2...).
- When creating EIP `[0]` → attach to instance `[0]`.
- When creating EIP `[1]` → attach to instance `[1]`.
- This ensures each instance gets exactly one unique EIP.

```hcl
  domain = "vpc"
```
- This EIP lives inside a VPC (Virtual Private Cloud).
- All modern AWS usage requires `domain = "vpc"`.
- The old value was `"standard"` (EC2-Classic, retired in 2022).
- Always use `"vpc"` in any current AWS account.

```hcl
  depends_on = [var.internet_gateway_id]
```
- `depends_on` tells Terraform: "wait for this thing to exist before creating the EIP".
- We pass the Internet Gateway ID from the networking module.
- Ensures IGW exists first so the EIP is immediately routable.
- **Why can't Terraform figure this out automatically?**
  Terraform tracks dependencies through resource references in arguments.
  The EIP's arguments don't directly reference the IGW, so Terraform
  doesn't know about the dependency — we must declare it explicitly.

```hcl
  tags = merge(var.common_tags, {
    Name = "${var.environment}-eip-${count.index}"
  })
```
- Tags the EIP with a name like `dev-eip-0`, `dev-eip-1`.
- Helps you find it in the AWS Console under EC2 → Elastic IPs.

---

## 📤 PART 5 — Outputs

Outputs expose values from this module to the parent (environment's `main.tf`).

```hcl
output "instance_ids" {
  value = aws_instance.app_server[*].id
}
```
- `[*]` is the **splat expression** — collect this attribute from ALL instances.
- Returns a list: `["i-0abc123", "i-0def456"]`
- Used by the CloudWatch module to create monitoring alarms.

```hcl
output "public_ips" {
  value      = aws_eip.app_server[*].public_ip
  depends_on = [aws_eip.app_server]
}
```
- Returns a list of static public IPs: `["52.10.20.30", "52.10.20.31"]`
- `output depends_on` — without this, Terraform might return null for the IP
  if the EIP association hasn't completed yet when the output is evaluated.
  This forces Terraform to wait for the EIP to be fully attached first.

```hcl
output "private_ips" {
  value = aws_instance.app_server[*].private_ip
}
```
- Returns private IPs inside the VPC: `["10.0.1.42", "10.0.1.43"]`
- Used for internal service-to-service calls that don't go over the internet.

```hcl
output "key_name" {
  value = aws_key_pair.devops.key_name
}
```
- The key pair name (`"devops"`).
- Other modules or resources that need to reference the same key can use this.

```hcl
output "ami_id" {
  value = data.aws_ami.ubuntu.id
}
```
- The actual AMI ID that was resolved at apply time.
- Useful for debugging — you can look up exactly which Ubuntu build was used.

---

## 🔌 How to Use This Module

```hcl
# environments/dev/main.tf

module "compute" {
  source = "../../modules/compute"

  environment          = "dev"
  key_name             = "devops"
  public_key_path      = "~/.ssh/id_rsa.pub"
  instance_type        = "t3.medium"
  instance_count       = 1
  public_subnet_id     = module.networking.public_subnet_ids[0]
  security_group_id    = module.security.ec2_security_group_id
  iam_instance_profile = module.iam.ec2_instance_profile_name
  internet_gateway_id  = module.networking.internet_gateway_id
  common_tags          = local.common_tags
}

# After apply — access the outputs:
output "server_ip" {
  value = module.compute.public_ips   # ["52.10.20.30"]
}
```

---

## 🔐 How to SSH Into the Instance

```bash
# After terraform apply, get the IP:
terraform output ec2_public_ips
# ["52.10.20.30"]

# SSH in (Ubuntu's default username is "ubuntu"):
ssh -i ~/.ssh/id_rsa ubuntu@52.10.20.30

# Check the user_data install log:
cat /var/log/user-data.log

# Verify Jenkins is running:
sudo systemctl status jenkins

# Verify Docker is running:
docker --version

# Verify Terraform is installed:
terraform version
```

---

## 📊 Variables Quick Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | — | `dev` / `test` / `prod` |
| `key_name` | string | `"devops"` | Name of the key pair in AWS |
| `public_key_path` | string | `~/.ssh/id_rsa.pub` | Path to your public key |
| `instance_type` | string | `"t3.medium"` | EC2 size |
| `instance_count` | number | `1` | How many EC2 instances |
| `public_subnet_id` | string | — | Subnet from networking module |
| `security_group_id` | string | — | SG from security module |
| `iam_instance_profile` | string | — | Profile from IAM module |
| `root_volume_size` | number | `30` | Disk size in GB |
| `internet_gateway_id` | string | — | IGW from networking module |
| `common_tags` | map(string) | `{}` | Tags applied to all resources |

---

## ⚡ Key Concepts Used in This Module

| Concept | Where | Why |
|---------|-------|-----|
| `data` source | `aws_ami` lookup | Never hardcode AMI IDs |
| `count` | instances + EIPs | Create N resources from 1 block |
| `count.index` | instance name + EIP attachment | Each resource gets unique name/pairing |
| `file()` function | `public_key`, `user_data` | Read files from disk at apply time |
| `path.module` | `user_data` script path | Always resolves correctly, any directory |
| `lifecycle ignore_changes` | instance AMI | Don't replace running servers on AMI update |
| `lifecycle create_before_destroy` | instance | Zero-downtime replacement |
| `depends_on` | EIP | IGW must exist before EIP is created |
| `output depends_on` | public_ips output | Wait for EIP association to complete |
| `merge()` | all tags | Combine common tags + resource-specific tags |
| `sensitive` | not here | See variables.tf — no secrets in compute |
