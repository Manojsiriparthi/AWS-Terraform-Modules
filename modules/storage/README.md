# 🪣 Module: Storage (S3)

> **Spoon-feeding guide — every single line explained.**

---

## 📦 What Does This Module Create?

| Resource | What it does |
|----------|-------------|
| `random_id` | Generates a unique suffix so bucket name is globally unique |
| `aws_s3_bucket` | The bucket itself |
| `aws_s3_bucket_public_access_block` | Blocks ALL public access (4 settings) |
| `aws_s3_bucket_versioning` | Keeps every version of every object |
| `aws_s3_bucket_server_side_encryption_configuration` | Encrypts all objects at rest |
| `aws_s3_bucket_lifecycle_configuration` | Auto-moves/deletes old objects to save cost |

---

## 🔍 PART 1 — Why S3?

S3 = Simple Storage Service. Object storage — store any file, any size.

**Used in this project for:**
- Terraform state files (remote backend)
- Application build artefacts from Jenkins
- Log files from EC2 and EKS
- Static assets

---

## 🔍 PART 2 — `random_id` and Bucket Naming

```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.bucket_name_prefix}-${var.environment}-${random_id.bucket_suffix.hex}"
}
```

**Why do S3 bucket names need to be globally unique?**

S3 bucket names share a single global namespace across ALL AWS accounts worldwide.
If you name a bucket `my-app-bucket`, and someone else already created that name
in their AWS account (even in a different region), your creation fails.

```
❌ WITHOUT random suffix:
  bucket = "terraform-learning-dev"
  Error: BucketAlreadyExists — someone already owns this name globally!

✅ WITH random suffix:
  bucket = "terraform-learning-dev-a1b2c3d4"
  The 8 hex chars (4 bytes = 32 bits = 4 billion combinations) make collision
  essentially impossible.
```

**`byte_length = 4`** — generates 4 random bytes → 8 hex characters e.g. `a1b2c3d4`.

**`random_id.bucket_suffix.hex`** — the `.hex` attribute gives us the hex string.

---

## 🔍 PART 3 — Lifecycle on the Bucket

```hcl
resource "aws_s3_bucket" "main" {
  lifecycle {
    prevent_destroy = false   # Set true in PROD
  }
}
```

**`prevent_destroy = false`**
- In dev/test: `false` so `terraform destroy` works freely.
- In production: set `true` to prevent accidental deletion.

```
prevent_destroy = true in prod:
  terraform destroy → Error: "Instance cannot be destroyed"
  You must manually remove the lifecycle block AND apply BEFORE destroying.
  This two-step process prevents accidents.
```

---

## 🔍 PART 4 — Public Access Block

```hcl
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

AWS S3 has had major data breaches because developers accidentally made buckets public.
This resource is a safety net — it blocks ALL public access regardless of any other settings.

**Each setting explained:**

| Setting | What it blocks |
|---------|---------------|
| `block_public_acls` | Prevents adding public ACLs (Access Control Lists) to objects |
| `block_public_policy` | Prevents bucket policies that grant public access |
| `ignore_public_acls` | Ignores any existing public ACLs (treats bucket as private) |
| `restrict_public_buckets` | Blocks public and cross-account access |

```
❌ WITHOUT this block:
  A developer adds bucket policy: { "Principal": "*", "Action": "s3:GetObject" }
  Bucket becomes public. Customer data exposed. Security incident.
  This happens more often than you'd think — AWS has a dedicated "S3 data breach" category.

✅ WITH this block:
  Even if someone adds a "make public" policy, this block overrides it.
  The bucket CANNOT become public, period.
  Always add this to every bucket that doesn't intentionally serve public content.
```

---

## 🔍 PART 5 — Versioning

```hcl
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}
```

**What is versioning?**
Every time you upload a file with the same name, S3 keeps the old version AND the new one.

```
WITHOUT versioning:
  Upload report.csv → version 1 (only copy)
  Upload report.csv again → version 1 REPLACED. Old data GONE FOREVER.
  Someone accidentally deletes app.jar → gone, no recovery.

WITH versioning:
  Upload report.csv → version 1
  Upload report.csv again → version 2 (version 1 still exists)
  Delete report.csv → creates a "delete marker" (file appears gone but version 1 still exists)
  Recover: remove the delete marker → report.csv is back.
```

**`var.versioning_enabled ? "Enabled" : "Suspended"`**
- Ternary expression: if variable is `true` → `"Enabled"`, else → `"Suspended"`.
- S3 doesn't have a simple `true/false` — it uses the strings `"Enabled"/"Suspended"`.
- `"Suspended"` pauses versioning (doesn't delete existing versions, just stops creating new ones).

---

## 🔍 PART 6 — Server-Side Encryption

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}
```

**What is SSE (Server-Side Encryption)?**
Every object stored in S3 is automatically encrypted before being written to disk.
When you read the object, AWS decrypts it automatically. Transparent to your app.

```
WITHOUT encryption:
  Data stored on AWS disk in plaintext.
  If AWS had a storage hardware incident, raw data could theoretically be read.
  Many compliance standards (HIPAA, PCI-DSS, SOC2) REQUIRE encryption at rest.

WITH encryption (AES256):
  Every object encrypted using 256-bit AES cipher.
  AWS manages the keys. No extra cost.
  Compliance checkbox: checked.
```

**`sse_algorithm = "AES256"`**
- AWS-managed keys (SSE-S3). Simple, free, no extra management.
- Alternative: `"aws:kms"` — use your own KMS key for more control and audit logs.

**`bucket_key_enabled = true`**
- When using KMS, normally AWS makes one API call to KMS *per object* encrypted.
  10,000 objects = 10,000 KMS API calls = higher cost.
- With `bucket_key_enabled = true`, AWS generates one key per bucket and caches it.
  Reduces KMS calls by ~99% and reduces cost significantly.
- For AES256, this has minimal impact but is good practice to enable.

---

## 🔍 PART 7 — Lifecycle Rules

**What is a lifecycle rule?**
An automated policy that moves or deletes objects based on age.
Saves money by automatically using cheaper storage tiers for old data.

**AWS S3 Storage Classes (cheapest to most expensive):**
```
STANDARD          → Hot data, frequently accessed
STANDARD_IA       → Infrequent Access, 60% cheaper, 30-day minimum
GLACIER           → Archival, hours to retrieve, 90% cheaper
DEEP_ARCHIVE      → Long-term archive, 12-hour retrieval, 95% cheaper
```

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  depends_on = [aws_s3_bucket_versioning.main]
  bucket     = aws_s3_bucket.main.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transition_days > 0 ? [1] : []
        content {
          days          = rule.value.transition_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days > 0 ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      noncurrent_version_expiration {
        noncurrent_days = 90
      }
    }
  }
}
```

**`depends_on = [aws_s3_bucket_versioning.main]`**
- Versioning must be fully enabled before lifecycle rules that reference
  `noncurrent_version_expiration` are applied. Otherwise AWS returns an error.

**`dynamic "rule"` with `for_each = var.lifecycle_rules`**
- Creates one lifecycle rule block per entry in the `lifecycle_rules` variable.
- Default rules:
  - `logs/` prefix: move to STANDARD_IA after 30 days, delete after 365 days
  - `tmp/` prefix: delete after 7 days

**`filter { prefix = rule.value.prefix }`**
- Apply this rule ONLY to objects whose key starts with this prefix.
- `logs/` → only objects like `logs/2024-01-15.log`
- Empty prefix `""` → applies to ALL objects in the bucket.

**`dynamic "transition"` with ternary `for_each`:**
```hcl
for_each = rule.value.transition_days > 0 ? [1] : []
```
- If `transition_days` is greater than 0, create the transition block (loop runs once with `[1]`).
- If `transition_days` is 0 (disabled), don't create it (empty list = no iterations).
- This is a common Terraform pattern to optionally include a block.

**`noncurrent_version_expiration { noncurrent_days = 90 }`**
- When versioning is on, old versions pile up and cost money.
- This deletes old (non-current) versions after 90 days.
- Current version is always kept; only superseded versions are cleaned up.

---

## 💰 Cost Saving Example

```
Without lifecycle rules:
  1 year of logs stored in STANDARD:  1 TB × $0.023/GB/month × 12 = $276/year

With lifecycle rules (transition to STANDARD_IA at 30 days):
  First 30 days in STANDARD:   1 TB × $0.023 × 1 month = $23
  11 months in STANDARD_IA:    1 TB × $0.0125 × 11 months = $137
  Total: $160/year — save $116/year per TB of logs
```

---

## ⚡ Key Concepts Used

| Concept | Where | Why |
|---------|-------|-----|
| `random_id` | bucket suffix | Globally unique name guaranteed |
| `lifecycle prevent_destroy` | bucket | Block accidental deletion in prod |
| `depends_on` | lifecycle config | Versioning must exist first |
| `dynamic` block | lifecycle rules | One rule block per variable entry |
| Nested `dynamic` | transition, expiration | Conditionally include optional blocks |
| Ternary operator | versioning status, dynamic for_each | Conditional value/block |
