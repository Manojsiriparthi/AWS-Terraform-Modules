# 🔒 Module: Security Groups

> **Spoon-feeding guide — every single line explained.**
> Security groups are the firewall of AWS. This module creates one for each service.

---

## 📦 What Does This Module Create?

| Resource | Protects |
|----------|---------|
| `aws_security_group.ec2` | EC2 instances — allows SSH, HTTPS, Jenkins |
| `aws_security_group.rds` | RDS database — only EC2 SG can reach it |
| `aws_security_group.eks_cluster` | EKS control plane — only worker nodes |
| `aws_security_group.eks_nodes` | EKS worker nodes — node-to-node + control plane |

---

## 🔍 What is a Security Group?

A security group is a **virtual firewall** attached to an AWS resource.

It has two rule types:
- **Ingress** = incoming traffic (who can connect TO this resource)
- **Egress** = outgoing traffic (where this resource can connect TO)

```
SECURITY GROUP RULES:
  Ingress: port 22  from 0.0.0.0/0 → ALLOW (SSH from anywhere)
  Ingress: port 8080 from 0.0.0.0/0 → ALLOW (Jenkins)
  Egress:  ALL traffic → ALLOW (EC2 can reach the internet)
  Anything not listed → DENY (implicit deny)
```

**Without a Security Group:**
You cannot attach an EC2 instance to a VPC without at least one security group.
AWS requires it. A security group with no rules = block everything.

**With a Security Group:**
Precise control. Database only accepts connections from EC2.
Internet can't directly reach the database.

---

## 🔍 PART 1 — EC2 Security Group

### What is a `dynamic` block?

Normally you'd write one `ingress` block per port:
```hcl
# ❌ WITHOUT dynamic block — repeated code:
ingress { from_port = 22;   to_port = 22;   protocol = "tcp" }
ingress { from_port = 443;  to_port = 443;  protocol = "tcp" }
ingress { from_port = 8080; to_port = 8080; protocol = "tcp" }
# If you need to add port 9000 later, you edit the .tf file.
# If different environments need different ports, you can't reuse this module.
```

```hcl
# ✅ WITH dynamic block — loop over a variable list:
dynamic "ingress" {
  for_each = var.ec2_ingress_rules   # variable list of rule objects
  content {
    from_port   = ingress.value.port
    to_port     = ingress.value.port
    protocol    = ingress.value.protocol
    cidr_blocks = ingress.value.cidr_blocks
  }
}
# To add port 9000: add one entry to ec2_ingress_rules in tfvars. Done.
# Different environment? Pass different rules. No code change needed.
```

### Line-by-Line: `resource "aws_security_group" "ec2"`

```hcl
resource "aws_security_group" "ec2" {
```
- Create a security group. `"ec2"` is the local Terraform name.

```hcl
  name = "${var.environment}-ec2-sg"
```
- The name shown in the AWS Console: `dev-ec2-sg`
- Must be unique within the VPC.

```hcl
  description = "Security group for EC2 app servers"
```
- Human-readable description. Always fill this — future-you will be grateful.

```hcl
  vpc_id = var.vpc_id
```
- Attach this security group to our VPC.
- Value comes from `module.networking.vpc_id`.
- Security groups are VPC-specific — you can't share them across VPCs.

```hcl
  dynamic "ingress" {
    for_each = var.ec2_ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
```
- Loops over `var.ec2_ingress_rules` (default: ports 22, 443, 8080).
- `ingress.value` = the current rule object `{ port=22, protocol="tcp", ... }`
- `from_port` and `to_port` are the same when opening a single port.
  Set them differently for a range (e.g. `from_port=8000, to_port=8999`).
- `protocol = "tcp"` — TCP for web/SSH. Use `"udp"` for DNS, `"-1"` for all.
- `cidr_blocks = ["0.0.0.0/0"]` — allow from any IP address.
  In production, restrict SSH to your office IP: `["203.0.113.0/32"]`

```hcl
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
```
- Allow ALL outbound traffic.
- `protocol = "-1"` means every protocol (TCP, UDP, ICMP, etc.).
- `from_port = 0, to_port = 0` means all ports.
- EC2 needs this to: install packages, pull Docker images, push to S3,
  reach Secrets Manager, talk to CloudWatch.
- Without egress rules: EC2 is isolated. Can't install anything. Useless.

```hcl
  lifecycle {
    create_before_destroy = true
  }
```
- When you change the security group (e.g., add a new port), Terraform
  must replace the SG (AWS doesn't allow renaming SGs).
- Without this: Terraform deletes old SG first → EC2 has no SG briefly → ERROR.
  AWS won't let you remove an SG that's attached to a running instance.
- With this: New SG created → EC2 updated to use new SG → old SG deleted. Safe.

---

## 🔍 PART 2 — RDS Security Group

```hcl
resource "aws_security_group" "rds" {
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
  ...
}
```

**Port 3306** — the default MySQL port.

**`security_groups = [aws_security_group.ec2.id]`**
This is the key security concept here.

```
❌ Using cidr_blocks = ["0.0.0.0/0"]:
  ANYONE on the internet can attempt to connect to your database.
  Brute-force attacks, SQL injection attempts, data theft.
  Never do this for a database!

❌ Using cidr_blocks = ["10.0.0.0/16"]:
  Only things inside the VPC can reach the DB.
  Better, but ANY resource in the VPC can reach it —
  including a compromised Lambda or misconfigured service.

✅ Using security_groups = [aws_security_group.ec2.id]:
  ONLY instances attached to the EC2 security group can reach the DB.
  Not the internet. Not other VPC resources. Only your EC2 app server.
  This is "least privilege" — minimum access needed, nothing more.
```

---

## 🔍 PART 3 — EKS Cluster Security Group

```hcl
resource "aws_security_group" "eks_cluster" {
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }
}
```

**Port 443** — the Kubernetes API server listens on HTTPS port 443.

**Why only port 443?**
- Worker nodes (kubelets) communicate with the control plane ONLY via HTTPS.
- `kubectl` commands also go via port 443.
- No other ports needed on the cluster SG.

**`security_groups = [aws_security_group.eks_nodes.id]`**
- Only EC2 instances in the nodes SG can talk to the API server.
- External traffic can't directly reach the EKS control plane.

---

## 🔍 PART 4 — EKS Nodes Security Group

```hcl
resource "aws_security_group" "eks_nodes" {

  # Rule 1: Node-to-node traffic
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Rule 2: Control plane to nodes
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }
}
```

**Rule 1 — `self = true` (node-to-node):**

```
self = true means:
  "Allow traffic from OTHER instances that also have THIS security group attached."

Why needed:
  Pod on Node A needs to call a service on Pod on Node B.
  Both nodes have the eks_nodes SG.
  Without this rule: pod-to-pod traffic is blocked. Kubernetes breaks.
  With this rule: nodes can freely communicate with each other.
```

**Rule 2 — Control plane to node kubelet (ports 1025-65535):**

```
Kubernetes control plane needs to:
  - Send commands to the kubelet agent on each node (port 10250)
  - Connect back for exec/logs/port-forward commands

Without this rule:
  kubectl exec → HANGS (control plane can't reach kubelet)
  kubectl logs → HANGS
  Pods can't report status back to the API server

Port range 1025-65535:
  AWS EKS recommends this range for control plane → node communication.
  Covers kubelet (10250) and other dynamic ports.
```

---

## 📊 Default Ingress Rules for EC2

Defined in `variables.tf` — override in tfvars per environment:

| Port | Protocol | CIDR | Purpose |
|------|----------|------|---------|
| 22 | tcp | 0.0.0.0/0 | SSH access |
| 443 | tcp | 0.0.0.0/0 | HTTPS |
| 8080 | tcp | 0.0.0.0/0 | Jenkins UI |

> ⚠️ **Production tip:** Change SSH CIDR to your office IP only: `["YOUR.IP.ADD.RESS/32"]`

---

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `dynamic` block | EC2 SG ingress | Loop over variable rules — no code repetition |
| `for_each` on var | inside dynamic | One ingress block per rule object |
| SG referencing SG | RDS, EKS cluster | Least privilege — not CIDR-based |
| `self = true` | EKS nodes | Allow instances with same SG to talk to each other |
| `lifecycle create_before_destroy` | All SGs | Prevent downtime during SG replacement |
| `protocol = "-1"` | egress, node-to-node | Allow ALL protocols and ports |
