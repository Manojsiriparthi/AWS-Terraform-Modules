# ==============================================================================
# MODULE: RDS — Outputs
# ==============================================================================

output "primary_endpoint" {
  description = "Connection endpoint for the primary (read-write) instance"
  value       = aws_db_instance.primary.endpoint
}

output "primary_instance_id" {
  description = "Identifier of the primary RDS instance"
  value       = aws_db_instance.primary.identifier
}

output "replica_endpoints" {
  description = "List of read replica endpoints"
  value       = aws_db_instance.replica[*].endpoint
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.primary.db_name
}

output "primary_arn" {
  description = "ARN of the primary RDS instance"
  value       = aws_db_instance.primary.arn
}
