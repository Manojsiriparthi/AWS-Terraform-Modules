# ==============================================================================
# MODULE: Storage (S3)
# PURPOSE: Create an S3 bucket with:
#   - Versioning (keeps history of every object)
#   - Server-side encryption (AES-256 at rest)
#   - Public access block (prevent accidental exposure)
#   - Lifecycle policy (auto-transition/delete old objects to save cost)
# CONCEPTS: lifecycle policy, for_each on lifecycle rules
# ==============================================================================

# ------------------------------------------------------------------------------
# S3 BUCKET
# A globally unique name is formed from a prefix + environment + random suffix.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "main" {
  # bucket name must be globally unique across ALL AWS accounts
  bucket = "${var.bucket_name_prefix}-${var.environment}-${random_id.bucket_suffix.hex}"

  # CONCEPT: lifecycle — prevent accidental deletion of a bucket with data
  lifecycle {
    prevent_destroy = false   # Set to true in PROD to block `terraform destroy`
  }

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-main-bucket"
    Environment = var.environment
  })
}

# Random suffix so the bucket name is globally unique
resource "random_id" "bucket_suffix" {
  byte_length = 4  # produces 8 hex chars, e.g. "a1b2c3d4"
}

# ------------------------------------------------------------------------------
# BLOCK ALL PUBLIC ACCESS
# Best practice: no S3 bucket should be public unless you explicitly need it.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# VERSIONING
# Keeps every version of every object. Protects against accidental deletes.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ------------------------------------------------------------------------------
# SERVER-SIDE ENCRYPTION (SSE-S3 = AES-256)
# All objects stored are encrypted by default.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"   # AWS-managed keys; use "aws:kms" for KMS keys
    }
    bucket_key_enabled = true    # Reduces KMS API calls and cost
  }
}

# ------------------------------------------------------------------------------
# LIFECYCLE RULES
# CONCEPT: for_each on a complex variable
# Automatically move old objects to cheaper storage tiers or delete them.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  # Versioning must be configured before lifecycle rules referencing versions
  depends_on = [aws_s3_bucket_versioning.main]

  bucket = aws_s3_bucket.main.id

  # CONCEPT: for_each — create one lifecycle rule per entry in the variable
  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix   # apply rule only to objects with this prefix
      }

      # Move to Standard-IA (Infrequent Access) after N days — 60% cheaper
      dynamic "transition" {
        for_each = rule.value.transition_days > 0 ? [1] : []
        content {
          days          = rule.value.transition_days
          storage_class = "STANDARD_IA"
        }
      }

      # Hard delete after N days
      dynamic "expiration" {
        for_each = rule.value.expiration_days > 0 ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      # Clean up old non-current versions (versioning leftovers)
      noncurrent_version_expiration {
        noncurrent_days = 90
      }
    }
  }
}
