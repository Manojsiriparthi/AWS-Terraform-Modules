# ☸️ Module: EKS (Elastic Kubernetes Service)

> **Spoon-feeding guide — every single line explained.**

---

## 📦 What Does This Module Create?

| Resource | What it is |
|----------|-----------|
| `aws_eks_cluster` | The Kubernetes control plane (AWS managed) |
| `aws_eks_node_group` | EC2 worker nodes that run your containers |
| `aws_eks_addon` (×4) | CoreDNS, kube-proxy, VPC CNI, EBS CSI — cluster plugins |

---

## 🔍 What is Kubernetes / EKS?

**Kubernetes** is a system that manages containerised applications.
Instead of manually starting/stopping Docker containers on EC2,
Kubernetes does it automatically — scheduling, scaling, restarting on failure.

**EKS** = AWS's managed Kubernetes.

```
WITHOUT EKS (self-managed):
  You run EC2 instances.
  You install Kubernetes master nodes manually (etcd, API server, scheduler...).
  You patch and upgrade them yourself.
  If a master node crashes, you fix it yourself.
  Takes weeks to set up correctly.

WITH EKS:
  AWS runs the control plane (master nodes) for you.
  You only manage worker nodes.
  AWS patches the control plane automatically.
  High availability built-in.
  You pay $0.10/hour and start deploying in 15 minutes.
```

**Architecture:**

```
                    ┌─────────────────────────────┐
                    │   EKS Control Plane (AWS)    │
                    │  API Server  |  Scheduler    │
                    │  etcd        |  Controller   │
                    └────────────┬────────────────┘
                                 │ kubectl commands
                                 │ node joins
                    ┌────────────▼────────────────┐
                    │      Node Group              │
                    │  ┌──────────┐ ┌──────────┐  │
                    │  │  Node 0  │ │  Node 1  │  │
                    │  │ (EC2 t3) │ │ (EC2 t3) │  │
                    │  │ Pod Pod  │ │ Pod Pod  │  │
                    │  └──────────┘ └──────────┘  │
                    └─────────────────────────────┘
```

---

## 🔍 PART 1 — EKS Cluster (Control Plane)

```hcl
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-eks-cluster"
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version
  ...
}
```

**`name`** — name of the cluster. Shown in AWS Console → EKS.
Used to configure `kubectl`: `aws eks update-kubeconfig --name dev-eks-cluster`

**`role_arn = var.cluster_role_arn`**
- The EKS control plane needs an IAM role to make AWS API calls on your behalf
  (manage load balancers, security groups, ENIs for pods).
- This comes from `module.iam.eks_cluster_role_arn`.
- Without this: EKS cannot manage networking for your pods. Cluster creation fails.

**`version = var.kubernetes_version`**
- Kubernetes version to use, e.g. `"1.29"`.
- EKS supports 3-4 versions at a time. Older versions become unsupported.
- Upgrade by changing this variable and running `terraform apply`.

### VPC Config

```hcl
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = var.public_access_enabled
  }
```

**`subnet_ids = var.private_subnet_ids`**
- The control plane places cross-account ENIs in these subnets.
- These ENIs are how worker nodes talk to the API server.
- We use private subnets — nodes never need public IPs.

**`endpoint_private_access = true`**
- The Kubernetes API server is reachable via a private endpoint inside the VPC.
- Your EC2 instance (with kubectl) can reach the cluster without going over the internet.

**`endpoint_public_access = var.public_access_enabled`**
- In dev/test: `true` — you can run `kubectl` from your laptop directly.
- In prod: `false` — API server only reachable from inside the VPC (via VPN or bastion).

```
endpoint_public_access = true:
  kubectl from your laptop → works directly
  Anyone on internet can reach the API server endpoint (protected by IAM auth)

endpoint_public_access = false (prod):
  kubectl from your laptop → fails unless on VPN/inside VPC
  Attackers can't even reach the API server to try credentials
  Stronger security posture
```

### Control Plane Logs

```hcl
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

All five log types sent to CloudWatch Logs:

| Log Type | What it captures |
|----------|-----------------|
| `api` | All API server requests (kubectl commands, pod scheduling) |
| `audit` | Who did what — security audit trail |
| `authenticator` | IAM authentication attempts |
| `controllerManager` | Deployment/replica set decisions |
| `scheduler` | Which node a pod was placed on |

**Without these logs:**
When a pod fails to start, you have no idea why. Was it a permission issue?
A scheduling failure? A networking problem? You're debugging blind.

### Lifecycle on the Cluster

```hcl
  lifecycle {
    ignore_changes = [
      vpc_config[0].security_group_ids,
    ]
  }
```

**Why ignore security group IDs?**
When you create an EKS cluster, AWS automatically creates and attaches its own
cluster security group (named `eks-cluster-sg-<name>-<id>`).
If Terraform doesn't ignore this, the next `plan` sees the extra SG and
tries to remove it → **cluster breaks**.

---

## 🔍 PART 2 — Managed Node Group

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-node-group"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = "AL2_x86_64"
  instance_types  = [var.node_instance_type]
  disk_size       = var.node_disk_size
  ...
}
```

**What is a Managed Node Group?**

```
Self-managed nodes (hard):
  You create EC2 instances manually.
  You install Kubernetes kubelet on each one.
  You manage patching, AMI updates, scaling.
  Node fails? You fix it manually.

Managed Node Group (easy):
  AWS creates the EC2s, installs the kubelet, joins the cluster.
  AWS patches the AMI. AWS replaces failed nodes.
  You configure desired/min/max size.
  You pick the instance type. AWS does the rest.
```

**`ami_type = "AL2_x86_64"`**
- Amazon Linux 2 optimised for EKS — pre-installed with kubelet, cni plugins, etc.
- This AMI is maintained by AWS and updated regularly with security patches.

**`instance_types = [var.node_instance_type]`** — default `"t3.medium"` (2 vCPU, 4GB RAM).

**`disk_size = var.node_disk_size`** — default 20GB. Holds OS, Docker images, pod logs.

### Scaling Config

```hcl
  scaling_config {
    desired_size = var.node_desired_count   # 2
    min_size     = var.node_min_count       # 1
    max_size     = var.node_max_count       # 4
  }
```

- `desired_size = 2` — start with 2 nodes.
- `min_size = 1` — never go below 1 node (even during scale-in).
- `max_size = 4` — auto-scaling can grow to 4 nodes under load.

### Update Config

```hcl
  update_config {
    max_unavailable = 1
  }
```

When updating nodes (new AMI, instance type change):
- Terminate nodes one at a time.
- Never take more than 1 node offline simultaneously.
- Ensures your workloads have somewhere to run during the update.

Without this: AWS might restart all nodes at once. All pods evicted. Downtime.

### `depends_on` on Node Group

```hcl
  depends_on = [
    aws_eks_cluster.main,
    var.node_role_policy_dependency,
  ]
```

**`aws_eks_cluster.main`** — nodes can't join a cluster that doesn't exist yet.
Terraform infers this from `cluster_name` but explicit is safer.

**`var.node_role_policy_dependency`** — the IAM policies must be attached to the
node role BEFORE nodes try to join the cluster. If nodes start before
`AmazonEKSWorkerNodePolicy` is attached, they get rejected by the cluster API.

### Lifecycle on Node Group

```hcl
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
```

**The problem without this:**

```
Cluster auto-scaler scales from 2 → 3 nodes under load.
AWS updates desired_size to 3 in the actual resource.
Engineer runs `terraform apply`.
Terraform sees: desired_size in state=3, desired_size in code=2.
Terraform scales DOWN to 2 — overriding the auto-scaler!
Pods get evicted. Performance drops.

With ignore_changes:
Terraform leaves desired_size alone after first creation.
Auto-scaler manages it freely.
```

---

## 🔍 PART 3 — EKS Add-ons

```hcl
resource "aws_eks_addon" "addons" {
  for_each = var.eks_addons

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = each.key
  addon_version            = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}
```

**`for_each = var.eks_addons`** — creates one addon per map entry.

```
each.key   = "coredns"
each.value = { version = "v1.11.1-eksbuild.4" }
```

**What each add-on does:**

| Add-on | Purpose | Without it |
|--------|---------|-----------|
| `coredns` | DNS inside the cluster — pods find services by name | Pods can't resolve `my-service.default.svc.cluster.local`. No service discovery. |
| `kube-proxy` | Maintains network rules for pod-to-service traffic | Services don't route correctly. Apps can't talk to each other. |
| `vpc-cni` | Assigns real VPC IPs to pods (not overlay network) | Pods can't communicate with RDS, ElastiCache, or other VPC resources. |
| `aws-ebs-csi-driver` | Kubernetes can create and attach EBS volumes | Persistent storage claims fail. Databases can't store data. |

**`resolve_conflicts_on_create/update = "OVERWRITE"`**
- If AWS or the cluster already has a version of this add-on configured,
  Terraform overwrites it with the specified version.
- Alternative: `"NONE"` — fail if conflicts exist (more conservative).

**`depends_on = [aws_eks_node_group.main]`**
- CoreDNS is a Deployment — it needs nodes to schedule its pods on.
- Creating CoreDNS before nodes exist → pods stuck in `Pending`.
- Wait for nodes to be `ACTIVE` before deploying add-ons.

---

## 🛠️ Using the Cluster After Apply

```bash
# Configure kubectl to talk to the new cluster
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(terraform output -raw eks_cluster_name)

# Verify cluster is accessible
kubectl get nodes
# NAME                          STATUS   ROLES    AGE
# ip-10-0-10-42.ec2.internal    Ready    <none>   5m

# Check add-ons are running
kubectl get pods -n kube-system
# coredns-xxx        Running
# kube-proxy-xxx     Running
# aws-node-xxx       Running   ← vpc-cni
```

---

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `depends_on` | node group, add-ons | Ordering: cluster before nodes, nodes before add-ons |
| `for_each` on map | add-ons | Deploy 4 add-ons from 1 resource block |
| `lifecycle ignore_changes` | cluster SG, node desired_size | Prevent Terraform fighting AWS/auto-scaler |
| `sensitive` output | cluster cert | Base64 cert never printed in terminal |
