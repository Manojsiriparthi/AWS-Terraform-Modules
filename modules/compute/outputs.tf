# ==============================================================================
# MODULE: Compute — Outputs
# Values exposed to the parent module / environment after apply.
# CONCEPT: output depends_on — when an output needs another resource to exist first
# ==============================================================================

# List of instance IDs (one per count index)
output "instance_ids" {
  description = "List of EC2 instance IDs"
  value       = aws_instance.app_server[*].id
}

# Public IPs assigned via Elastic IPs
output "public_ips" {
  description = "List of Elastic (static) public IPs"
  value       = aws_eip.app_server[*].public_ip

  # CONCEPT: output depends_on
  # The EIPs must be fully associated before this output is accurate.
  depends_on = [aws_eip.app_server]
}

# Private IPs (useful for internal service calls)
output "private_ips" {
  description = "List of private IPs inside the VPC"
  value       = aws_instance.app_server[*].private_ip
}

# Key pair name — consumed by other modules that need to reference the key
output "key_name" {
  description = "Name of the created key pair"
  value       = aws_key_pair.devops.key_name
}

# AMI that was selected at apply time
output "ami_id" {
  description = "AMI ID used for the instances"
  value       = data.aws_ami.ubuntu.id
}
