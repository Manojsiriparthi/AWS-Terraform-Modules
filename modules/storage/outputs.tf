# ==============================================================================
# MODULE: Storage — Outputs
# ==============================================================================

output "bucket_id" {
  description = "The name/ID of the S3 bucket"
  value       = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket — used in IAM policies"
  value       = aws_s3_bucket.main.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name for the bucket (useful for CloudFront origins)"
  value       = aws_s3_bucket.main.bucket_regional_domain_name
}
