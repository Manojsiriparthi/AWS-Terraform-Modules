# 🔑 Module: IAM (Identity and Access Management)

> **Spoon-feeding guide — every single line explained.**
> IAM is the permission system of AWS. Nothing works without the right permissions.

---

## 📦 What Does This Module Create?

| Resource | Purpose |
|----------|---------|
| `aws_iam_role.ec2` | The identity EC2 instances assume |
| `aws_iam_role_policy_attachment.ec2_ssm` | EC2 → SSM Session Manager (no SSH) |
| `aws_iam_role_policy_attachment.ec2_cloudwatch` | EC2 → push metrics/logs |
| `aws_iam_policy.ec2_s3` | Custom policy: EC2 read/write one specific S3 bucket |
| `aws_iam_role_policy_attachment.ec2_s3` | Attaches S3 policy to EC2 role |
| `aws_iam_role_policy_attachment.ec2_secrets` | EC2 → read RDS password from Secrets Manager |
| `aws_iam_instance_profile.ec2` | Wrapper that lets EC2 use the role |
| `aws_iam_role.eks_cluster` | Identity the EKS control plane assumes |
| `aws_iam_role_policy_attachment.eks_cluster` | EKS cluster → manage AWS resources |
| `aws_iam_role.eks_nodes` | Identity worker nodes assume |
| `aws_iam_role_policy_attachment.eks_nodes` | Nodes → join cluster, pull images |

---

## 🔍 What is IAM?

IAM = Identity and Access Management. It answers one question:
> "Which AWS service or user is ALLOWED to do WHAT to WHICH resource?"

**Why does EC2 need an IAM role?**
When your EC2 instance runs `aws s3 cp file.txt s3://my-bucket/`, it needs permission.
Without a role, AWS rejects the request: `AccessDenied`.

**How it works:**

```
EC2 Instance
  │ "I want to upload to S3"
  ▼
IAM Role attached to EC2
  │ "Does this role have s3:PutObject permission?"
  ▼
IAM Policy attached to Role
  │ "Yes! Allowed on bucket arn:aws:s3:::my-bucket"
  ▼
S3
  └── Upload succeeds ✅
```

---

## 🔍 PART 1 — Trust Policy (Who Can Assume the Role)

```hcl
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
```

**What is a trust policy?**
Every IAM role has TWO parts:
1. **Trust policy** — WHO can use this role (assume it)
2. **Permission policy** — WHAT actions the role can perform

This block defines the trust policy.

**`actions = ["sts:AssumeRole"]`**
- `sts` = Security Token Service.
- `AssumeRole` = the action of "becoming" a role to get temporary credentials.
- This is the only action needed in a trust policy.

**`principals { type = "Service"; identifiers = ["ec2.amazonaws.com"] }`**
- `type = "Service"` — the principal is an AWS service (not a user or another account).
- `identifiers = ["ec2.amazonaws.com"]` — specifically the EC2 service.
- This means: "ONLY EC2 instances can assume this role."
- Without this: no one can use the role — it's created but useless.

**`data "aws_iam_policy_document"`** — a data source that generates the JSON policy.

```
❌ Without data source — manual JSON string (error-prone):
assume_role_policy = <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow"...}]}
EOF

✅ With data source — structured HCL (validated, readable):
assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
```

---

## 🔍 PART 2 — EC2 IAM Role

```hcl
resource "aws_iam_role" "ec2" {
  name               = "${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  ...
}
```

**`name`** — role name shown in AWS Console → IAM → Roles.

**`assume_role_policy`** — the trust policy from above. Answers "who can use this role."

The role itself has NO permissions yet. Permissions are added by attaching policies below.

---

## 🔍 PART 3 — Policy Attachments

### SSM Session Manager

```hcl
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

**What is SSM Session Manager?**
```
TRADITIONAL approach:
  Open port 22 (SSH) on security group
  Manage SSH keys for every engineer
  Track who has access
  Keys can be leaked/stolen

WITH SSM Session Manager:
  Port 22 is CLOSED — no inbound SSH needed
  Engineers connect via AWS Console or CLI:
    aws ssm start-session --target i-0abc123
  Access controlled by IAM, not SSH keys
  Every session logged to CloudWatch
  No key management headache
```

`AmazonSSMManagedInstanceCore` is the AWS-managed policy that grants
everything SSM needs: register the instance, open sessions, run commands.

### CloudWatch Agent

```hcl
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

Allows the CloudWatch agent running on EC2 to push custom metrics and logs.
Without this: `PutMetricData` returns `AccessDenied`. Your dashboards stay empty.

---

## 🔍 PART 4 — Custom S3 Policy (Least Privilege)

```hcl
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
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }
}
```

**Why not just attach `AmazonS3FullAccess`?**

```
AmazonS3FullAccess gives:
  s3:* on resource: *
  = EC2 can read/write/delete EVERY bucket in your AWS account
  If EC2 is compromised, attacker can access ALL your data.

Custom policy gives:
  4 specific actions on 1 specific bucket only
  If EC2 is compromised, attacker can only touch that one bucket.
  This is "least privilege" — minimum permissions needed.
```

**`sid = "S3BucketAccess"`** — Statement ID. A label for this permission block.
Useful for debugging which policy statement was matched in access logs.

**`effect = "Allow"`** — explicitly allow these actions.
Default is deny, so you must explicitly allow what you want.

**`resources` — why two entries?**

```
var.s3_bucket_arn          = "arn:aws:s3:::my-bucket"
"${var.s3_bucket_arn}/*"   = "arn:aws:s3:::my-bucket/*"

s3:ListBucket  requires the BUCKET ARN (not the object path)
s3:GetObject,
s3:PutObject,
s3:DeleteObject require the OBJECT ARN (bucket/* with wildcard)

Without both:
  ListBucket → AccessDenied (needs bucket ARN)
  GetObject  → AccessDenied (needs /*  ARN)
Include both → everything works.
```

---

## 🔍 PART 5 — Secrets Manager Attachment

```hcl
resource "aws_iam_role_policy_attachment" "ec2_secrets" {
  count = var.secrets_read_policy_arn != "" ? 1 : 0

  role       = aws_iam_role.ec2.name
  policy_arn = var.secrets_read_policy_arn

  depends_on = [aws_iam_role.ec2]
}
```

**`count = var.secrets_read_policy_arn != "" ? 1 : 0`**
- If a secrets policy ARN is provided (not empty string) → create 1 attachment.
- If empty string → create 0 attachments (skip this resource entirely).
- This is the `count` trick for optional resources (on/off toggle).

**`depends_on = [aws_iam_role.ec2]`**
- The role must exist before we can attach a policy to it.
- Terraform normally infers this from the `role` argument, but explicit is safer.

**Why attach secrets access?**
EC2 application code can now do:
```python
import boto3
client = boto3.client('secretsmanager')
secret = client.get_secret_value(SecretId='dev/rds/master-password')
# Returns: {"username": "admin", "password": "Xk9#mP...", "engine": "mysql"}
```
No hardcoded password in app code. No password in environment variables.

---

## 🔍 PART 6 — Instance Profile

```hcl
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}
```

**Why do we need an instance profile?**

You cannot directly attach an IAM Role to an EC2 instance.
You must wrap the role in an **Instance Profile** first.
Think of it as a container that holds the role for EC2.

```
IAM Role → (wrapped in) → Instance Profile → (attached to) → EC2 Instance
```

The instance profile name is what goes in the `iam_instance_profile` argument
of `aws_instance`. The compute module receives this as output:
`module.iam.ec2_instance_profile_name`

---

## 🔍 PART 7 — EKS Cluster Role

```hcl
locals {
  eks_cluster_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ])
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  for_each = local.eks_cluster_policies

  role       = aws_iam_role.eks_cluster.name
  policy_arn = each.value
}
```

**Why `toset()`?**
`for_each` requires a **set or map**, not a list.
`toset()` converts a list to a set (removes duplicates, makes it unordered).

**`for_each = local.eks_cluster_policies`**
Creates one attachment per policy ARN. `each.value` = the ARN string.

**What each policy grants:**

| Policy | Why needed |
|--------|-----------|
| `AmazonEKSClusterPolicy` | Core permissions: manage nodes, update cluster config |
| `AmazonEKSVPCResourceController` | Manage ENIs and IPs for pods (required for VPC CNI) |

---

## 🔍 PART 8 — EKS Node Role

```hcl
locals {
  eks_node_policies = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
}
```

| Policy | Why needed |
|--------|-----------|
| `AmazonEKSWorkerNodePolicy` | Join the cluster, describe EC2 instances |
| `AmazonEKS_CNI_Policy` | VPC CNI plugin: assign pod IPs, manage ENIs |
| `AmazonEC2ContainerRegistryReadOnly` | Pull Docker images from ECR |
| `CloudWatchAgentServerPolicy` | Push node metrics and logs to CloudWatch |

Without `AmazonEC2ContainerRegistryReadOnly`:
Kubernetes can't pull your container images. Pods stay in `ImagePullBackOff` state forever.

---

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `data aws_iam_policy_document` | trust policies, S3 policy | Structured JSON generation |
| `count` with ternary | secrets attachment | Optional resource on/off toggle |
| `for_each` + `toset()` | EKS cluster + node policy attachments | Multiple policies from one resource block |
| `depends_on` | S3 attachment, secrets attachment | Explicit ordering |
| `locals` with `toset` | EKS policy ARN sets | Clean reusable sets |
| Least privilege | S3 policy | Only 4 actions on 1 bucket — not s3:* |
| Instance Profile | EC2 profile | Required wrapper to attach role to EC2 |
